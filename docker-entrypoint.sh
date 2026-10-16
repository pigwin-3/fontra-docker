#!/bin/sh
# Starts Fontra with the image's server options.
#
# In filesystem mode it first creates an empty font, named by
# FONTRA_DEFAULT_FONT (default: default.designspace), when the fonts folder
# is empty. Hidden files such as .gitkeep don't count. Set
# FONTRA_DEFAULT_FONT to an empty value to turn this off.
set -eu

if [ "${1:-}" = filesystem ] && [ -n "${FONTRA_DEFAULT_FONT:-}" ]; then
    root=
    readOnly=false
    skipNext=true # the "filesystem" argument itself
    for arg in "$@"; do
        if [ "$skipNext" = true ]; then
            skipNext=false
            continue
        fi
        case "$arg" in
            --read-only) readOnly=true ;;
            --max-folder-depth) skipNext=true ;;
            -*) ;;
            *) if [ -z "$root" ]; then root=$arg; fi ;;
        esac
    done

    if [ "$readOnly" = false ] && [ -d "$root" ]; then
        empty=true
        for entry in "$root"/*; do
            if [ -e "$entry" ] || [ -L "$entry" ]; then
                empty=false
                break
            fi
        done
        if [ "$empty" = true ]; then
            echo "The fonts folder is empty, creating $FONTRA_DEFAULT_FONT"
            fontra new "${root%/}/$FONTRA_DEFAULT_FONT" ||
                echo "Could not create $FONTRA_DEFAULT_FONT, starting without it." >&2
        fi
    fi
fi

exec fontra --host 0.0.0.0 --http-port 8000 "$@"
