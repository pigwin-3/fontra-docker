#!/bin/sh
# Copies an existing font into the multi-user database, so that everyone
# with access to the project can open it in Fontra.
#
# Usage: ./import-font.sh [--skip-bad-glyphs] FONT PROJECT [NAME]
#
#   FONT     a .designspace, .ufo, .fontra, .ttf, .otf or .rcjk
#   PROJECT  project to add the font to, created if it doesn't exist
#   NAME     font name within the project (default: FONT's file name)
#
#   --skip-bad-glyphs  leave out glyphs the .rcjk format can't store, such
#                      as glyphs with skewed components, instead of stopping
#
# Run it while the stack is up. New projects get the admin account as
# designer; add more people on the project's page in the admin site.
# Importing again under the same name replaces the font's glyphs.
# A .designspace is sent together with the rest of its folder, so its
# sources should live in that folder.
#
# Set COMPOSE="podman compose" to use Podman instead of Docker.
set -eu

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" >&2
}

skip=
case "${1:-}" in
    --skip-bad-glyphs) skip=--skip-bad-glyphs; shift ;;
    -h | --help) usage; exit 0 ;;
esac
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    usage
    exit 2
fi

font=${1%/}
project=$2
here=$(cd "$(dirname "$0")" && pwd)

# Run compose from this folder, so it finds the compose file and .env here.
compose() {
    (cd "$here" && ${COMPOSE:-docker compose} "$@")
}

if [ ! -e "$font" ]; then
    echo "import-font.sh: $font does not exist" >&2
    exit 1
fi
base=$(basename "$font")
dir=$(cd "$(dirname "$font")" && pwd)
name=${3:-${base%.*}}

case "$base" in
    *.designspace) items=. ;;
    *) items=$base ;;
esac

if ! compose ps --status running --services | grep -qx robocjk; then
    echo "import-font.sh: the robocjk service is not running, start the stack first" >&2
    exit 1
fi

zip=$(mktemp)
trap 'rm -f "$zip"' EXIT

# Step 1, in the fontra image: convert the font with fontra-copy, and send it
# back as a zipped .rcjk folder. The .rcjk format has no place for designspace
# rules (conditional substitutions), so those are left out with a warning
# instead of failing the whole copy. With --skip-bad-glyphs, glyphs that fail
# to convert are left out too.
echo "Converting $base to the .rcjk format..." >&2
# The quoted script runs in the container, which expands its variables.
# shellcheck disable=SC2016
if ! tar -C "$dir" -cf - "$items" | compose run --rm -T --no-deps --entrypoint sh fontra -c '
set -eu
mkdir -p /tmp/in /tmp/out
tar -C /tmp/in -xf -
python - "/tmp/in/$1" /tmp/out/font.rcjk ${2:+"$2"} >&2 <<"PYTHON"
import sys
from fontra.backends.copy import main
from fontra_rcjk.backend_fs import RCJKBackend

skipBadGlyphs = "--skip-bad-glyphs" in sys.argv
sys.argv = ["fontra-copy"] + [a for a in sys.argv[1:] if a != "--skip-bad-glyphs"]
skipped = []


async def putConditionalSubstitutions(self, substitutions):
    if substitutions.rules:
        print("Warning: leaving out the conditional substitutions (designspace"
              " rules), the database cannot store them.", file=sys.stderr)


RCJKBackend.putConditionalSubstitutions = putConditionalSubstitutions

if skipBadGlyphs:
    sys.argv.append("--continue-on-error")
    putGlyph = RCJKBackend.putGlyph

    async def putGlyphOrSkip(self, glyphName, glyph, codePoints):
        try:
            await putGlyph(self, glyphName, glyph, codePoints)
        except Exception as error:
            print(f"Leaving out glyph {glyphName}: {error}", file=sys.stderr)
            skipped.append(glyphName)

    RCJKBackend.putGlyph = putGlyphOrSkip

main()
if skipped:
    names = ", ".join(skipped)
    print(f"Left out {len(skipped)} glyphs: {names}", file=sys.stderr)
PYTHON
cd /tmp/out
python -m zipfile -c /tmp/font.zip font.rcjk
cat /tmp/font.zip
' sh "$base" "$skip" > "$zip"; then
    echo "import-font.sh: converting $base failed, see the messages above." >&2
    [ -n "$skip" ] || echo "If a glyph failed to convert, --skip-bad-glyphs leaves such glyphs out." >&2
    exit 1
fi

# Step 2, in the robocjk container: create the project and font if needed,
# then load the .rcjk data into the database.
echo "Importing it into project '$project' as '$name'..." >&2
# The quoted script runs in the container, which expands its variables.
# shellcheck disable=SC2016
compose exec -T robocjk sh -c '
set -eu
zip=/tmp/import-$$.zip
cat > "$zip"
status=0
python /srv/robocjk/import_font.py "$1" "$2" "$zip" || status=$?
rm -f "$zip"
exit "$status"
' sh "$project" "$name" < "$zip"
