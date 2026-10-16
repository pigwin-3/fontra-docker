#!/bin/sh
# Runs before every command in the robocjk container. When the server starts,
# it first prepares the database (see bootstrap.py).
set -eu

mkdir -p /data/logs /data/cache /data/media /data/git

if [ "${1:-}" = gunicorn ]; then
    python /srv/robocjk/bootstrap.py
fi

exec "$@"
