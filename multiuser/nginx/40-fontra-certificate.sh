#!/bin/sh
# Creates a self-signed certificate on first start, unless the certs folder
# already holds fullchain.pem and privkey.pem (for example from Let's Encrypt).
set -eu

dir=/etc/nginx/certs
host="${PUBLIC_HOST:-localhost}"

if [ -s "$dir/fullchain.pem" ] && [ -s "$dir/privkey.pem" ]; then
    exit 0
fi

case "$host" in
    *[!0-9.]*) names="DNS:$host" ;;
    *) names="IP:$host" ;;
esac
for extra in DNS:localhost DNS:proxy IP:127.0.0.1; do
    case ",$names," in
        *",$extra,"*) ;;
        *) names="$names,$extra" ;;
    esac
done

echo "$0: no certificate in $dir, creating a self-signed one for $names"
mkdir -p "$dir"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 825 \
    -subj "/CN=$host" -addext "subjectAltName=$names" \
    -keyout "$dir/privkey.pem" -out "$dir/fullchain.pem" 2>/dev/null
chmod 600 "$dir/privkey.pem"
