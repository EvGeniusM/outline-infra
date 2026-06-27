#!/usr/bin/env sh
set -eu
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cd "$(dirname "$0")/.."

env_var() { grep "^${1}=" .env | cut -d= -f2-; }
POSTGRES_USER=$(env_var POSTGRES_USER)
POSTGRES_DB=$(env_var POSTGRES_DB)
MINIO_ROOT_USER=$(env_var MINIO_ROOT_USER)
MINIO_ROOT_PASSWORD=$(env_var MINIO_ROOT_PASSWORD)
AWS_S3_UPLOAD_BUCKET_NAME=$(env_var AWS_S3_UPLOAD_BUCKET_NAME)
PLANE_DB=$(env_var PLANE_DB)
PLANE_S3_BUCKET_NAME=$(env_var PLANE_S3_BUCKET_NAME)

TS=$(date +%Y%m%d-%H%M%S)
WORKDIR="backups/${TS}"
KEEP=7

mkdir -p "$WORKDIR/minio"

echo "Дамп postgres..."
docker compose exec -T postgres pg_dump --clean --if-exists -U "$POSTGRES_USER" "$POSTGRES_DB" \
  | gzip > "$WORKDIR/postgres.sql.gz"

echo "Дамп postgres (БД ${PLANE_DB})..."
docker compose exec -T postgres pg_dump --clean --if-exists -U "$POSTGRES_USER" "$PLANE_DB" \
  | gzip > "$WORKDIR/plane.sql.gz"

echo "Дамп minio (бакеты ${AWS_S3_UPLOAD_BUCKET_NAME}, ${PLANE_S3_BUCKET_NAME})..."
docker run --rm \
  --network outline-infra_default \
  --entrypoint sh \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$(pwd)/$WORKDIR/minio:/backup" \
  minio/mc -c "
    mc alias set local http://minio:9000 '$MINIO_ROOT_USER' '$MINIO_ROOT_PASSWORD' >/dev/null &&
    mc mirror --quiet local/$AWS_S3_UPLOAD_BUCKET_NAME /backup/$AWS_S3_UPLOAD_BUCKET_NAME &&
    mc mirror --quiet local/$PLANE_S3_BUCKET_NAME /backup/$PLANE_S3_BUCKET_NAME
  "

tar -C backups -czf "backups/${TS}.tar.gz" "${TS}"
rm -rf "$WORKDIR"
echo "Бэкап сохранён: backups/${TS}.tar.gz"

COUNT=$(ls backups/*.tar.gz 2>/dev/null | wc -l)
if [ "$COUNT" -gt "$KEEP" ]; then
  ls -1t backups/*.tar.gz | tail -n +$((KEEP + 1)) | while IFS= read -r old; do
    echo "Удаляю старый бэкап: $old"
    rm -f "$old"
  done
fi
