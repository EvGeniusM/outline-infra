#!/usr/bin/env sh
set -eu
PASSWORD="${1:-password}"
docker run --rm httpd:2 htpasswd -nbBC 10 "" "$PASSWORD" \
  | cut -d: -f2 \
  | sed 's/^\$2y/\$2a/'
