#!/bin/sh
# Creates .env from .env.example with random secrets and a random admin
# password. Optional argument: the PUBLIC_HOST value (default: localhost).
#
#   ./init-env.sh                     # for trying it out on this machine
#   ./init-env.sh fonts.example.com   # for a server
set -eu
cd "$(dirname "$0")"

if [ -e .env ]; then
    echo "init-env.sh: .env already exists, remove it first to start over." >&2
    exit 1
fi

host="${1:-}"

random() {
    od -An -tx1 -N24 /dev/urandom | tr -d ' \n'
}

umask 077
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ADMIN_PASSWORD= | MYSQL_PASSWORD= | MYSQL_ROOT_PASSWORD= | \
        DJANGO_SECRET_KEY= | JWT_SECRET= | HASHIDS_SALT=)
            printf '%s%s\n' "$line" "$(random)" ;;
        PUBLIC_HOST=*)
            printf 'PUBLIC_HOST=%s\n' "${host:-${line#PUBLIC_HOST=}}" ;;
        *)
            printf '%s\n' "$line" ;;
    esac
done < .env.example > .env

echo "Created .env. Admin login:"
sed -n 's/^ADMIN_USERNAME=/  username: /p; s/^ADMIN_PASSWORD=/  password: /p' .env
