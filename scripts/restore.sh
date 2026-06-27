#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."

env_var() { grep "^${1}=" .env | cut -d= -f2-; }
POSTGRES_USER=$(env_var POSTGRES_USER)
POSTGRES_DB=$(env_var POSTGRES_DB)
MINIO_ROOT_USER=$(env_var MINIO_ROOT_USER)
MINIO_ROOT_PASSWORD=$(env_var MINIO_ROOT_PASSWORD)
AWS_S3_UPLOAD_BUCKET_NAME=$(env_var AWS_S3_UPLOAD_BUCKET_NAME)
PLANE_DB=$(env_var PLANE_DB)
PLANE_S3_BUCKET_NAME=$(env_var PLANE_S3_BUCKET_NAME)

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  echo "Использование: sh scripts/restore.sh backups/<TS>.tar.gz" >&2
  exit 1
fi

printf 'Это перезапишет текущие данные postgres и minio. Продолжить? [y/N] '
read -r CONFIRM
case "$CONFIRM" in
  y|Y) ;;
  *) echo "Отменено."; exit 1 ;;
esac

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

tar -xzf "$ARCHIVE" -C "$WORKDIR"
TS_DIR=$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -1)

echo "Восстанавливаю postgres..."
gunzip -c "$TS_DIR/postgres.sql.gz" | docker compose exec -T postgres psql -U "$POSTGRES_USER" "$POSTGRES_DB"

echo "Восстанавливаю postgres (БД ${PLANE_DB})..."
gunzip -c "$TS_DIR/plane.sql.gz" | docker compose exec -T postgres psql -U "$POSTGRES_USER" "$PLANE_DB"

echo "Восстанавливаю minio (бакеты ${AWS_S3_UPLOAD_BUCKET_NAME}, ${PLANE_S3_BUCKET_NAME})..."
docker run --rm \
  --network outline-infra_default \
  --entrypoint sh \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$TS_DIR/minio:/backup" \
  minio/mc -c "
    mc alias set local http://minio:9000 '$MINIO_ROOT_USER' '$MINIO_ROOT_PASSWORD' >/dev/null &&
    mc mirror --quiet --overwrite /backup/$AWS_S3_UPLOAD_BUCKET_NAME local/$AWS_S3_UPLOAD_BUCKET_NAME &&
    mc mirror --quiet --overwrite /backup/$PLANE_S3_BUCKET_NAME local/$PLANE_S3_BUCKET_NAME
  "

echo "Восстановление из ${ARCHIVE} завершено."
