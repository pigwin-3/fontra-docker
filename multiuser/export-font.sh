#!/bin/sh
# Copies a font from the multi-user database to files on this machine.
#
# Usage: ./export-font.sh PROJECT/FONT OUTPUT
#
#   PROJECT/FONT  the font as Fontra lists it, for example "My Project/MyFont"
#   OUTPUT        file to write: a .designspace (written with its UFOs next
#                 to it), .ufo, .fontra or .rcjk
#
# Run it while the stack is up. It logs in as the admin account from .env,
# which must be a designer of the project; set EXPORT_USER and
# EXPORT_PASSWORD to use another account. The database stores no kerning
# and no designspace rules, so the output has none either.
#
# Set COMPOSE="podman compose" to use Podman instead of Docker.
set -eu

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" >&2
}

case "${1:-}" in
    -h | --help) usage; exit 0 ;;
esac
if [ $# -ne 2 ]; then
    usage
    exit 2
fi

font=$1
output=$2
here=$(cd "$(dirname "$0")" && pwd)

# Run compose from this folder, so it finds the compose file and .env here.
compose() {
    (cd "$here" && ${COMPOSE:-docker compose} "$@")
}

name=$(basename "$output")
case "$name" in
    *.designspace | *.ufo | *.fontra | *.rcjk) ;;
    *)
        echo "export-font.sh: OUTPUT must end in .designspace, .ufo, .fontra or .rcjk" >&2
        exit 2
        ;;
esac
if [ -e "$output" ]; then
    echo "export-font.sh: $output already exists" >&2
    exit 1
fi
mkdir -p "$(dirname "$output")"
outdir=$(cd "$(dirname "$output")" && pwd)

if ! compose ps --status running --services | grep -qx proxy; then
    echo "export-font.sh: the stack is not running, start it first" >&2
    exit 1
fi

EXPORT_USER=${EXPORT_USER:-$(sed -n 's/^ADMIN_USERNAME=//p' "$here/.env")}
EXPORT_PASSWORD=${EXPORT_PASSWORD:-$(sed -n 's/^ADMIN_PASSWORD=//p' "$here/.env")}
export EXPORT_USER EXPORT_PASSWORD

archive=$(mktemp)
trap 'rm -f "$archive"' EXIT

# In the fontra image: log in to django-robo-cjk like Fontra does, read the
# font through Fontra's database backend, write it with fontra-copy's copy
# routine, and send the result back as a tar archive.
echo "Exporting $font..." >&2
# The quoted script runs in the container, which expands its variables.
# shellcheck disable=SC2016
compose run --rm -T --no-deps -e EXPORT_USER -e EXPORT_PASSWORD \
    --entrypoint sh fontra -c '
set -eu
mkdir -p /tmp/out
python - "$1" "/tmp/out/$2" >&2 <<"PYTHON"
import asyncio
import logging
import os
import pathlib
import sys
from contextlib import aclosing

from fontra.backends import newFileSystemBackend
from fontra.backends.copy import copyFont
from fontra_rcjk.backend_mysql import RCJKMySQLBackend
from fontra_rcjk.client_async import RCJKClientAsync


async def main(fontName, destPath):
    user = os.environ["EXPORT_USER"]
    client = RCJKClientAsync(
        host="https://proxy:9443/",
        username=user,
        password=os.environ["EXPORT_PASSWORD"],
    )
    try:
        await client.connect()
    except Exception as error:
        await client.close()
        sys.exit(f"Could not log in as {user}: {error}")
    try:
        fonts = {
            f"{project}/{font}": uids
            for (project, font), uids in (await client.get_project_font_uid_mapping()).items()
        }
        if fontName not in fonts:
            available = ", ".join(sorted(fonts)) or "none"
            sys.exit(f"No font {fontName!r} for this account. Available: {available}")
        source = RCJKMySQLBackend.fromRCJKClient(client, fonts[fontName][1])
        dest = newFileSystemBackend(pathlib.Path(destPath))
        async with aclosing(source), aclosing(dest):
            await copyFont(source, dest)
    finally:
        await client.close()


logging.basicConfig(level=logging.INFO, format="%(name)s %(levelname)s %(message)s")
asyncio.run(main(sys.argv[1], sys.argv[2]))
PYTHON
tar -C /tmp/out -cf - .
' sh "$font" "$name" > "$archive"

tar -C "$outdir" -xf "$archive"
echo "Wrote $outdir/$name" >&2
