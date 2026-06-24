#!/usr/bin/env sh
set -eu
PASSWORD="${1:-password}"
# htpasswd из образа httpd; нормализуем префикс к $2a (его понимает Dex)
docker run --rm httpd:2 htpasswd -nbBC 10 "" "$PASSWORD" \
  | cut -d: -f2 \
  | sed 's/^\$2y/\$2a/'
