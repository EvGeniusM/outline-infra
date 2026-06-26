#!/usr/bin/env sh
set -eu

until pg_isready -h postgres -U "$POSTGRES_USER" >/dev/null 2>&1; do
  echo "Жду postgres..."
  sleep 2
done

if psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
     "SELECT 1 FROM pg_database WHERE datname='$PLANE_DB'" | grep -q 1; then
  echo "БД '$PLANE_DB' уже существует"
else
  psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE DATABASE \"$PLANE_DB\""
  echo "БД '$PLANE_DB' создана"
fi
