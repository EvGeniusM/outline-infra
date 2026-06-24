#!/usr/bin/env sh
set -eu

until mc alias set local "http://minio:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; do
  echo "Жду minio..."
  sleep 2
done

mc mb --ignore-existing local/"$AWS_S3_UPLOAD_BUCKET_NAME"
echo "Bucket '$AWS_S3_UPLOAD_BUCKET_NAME' готов"

mc anonymous set download local/"$AWS_S3_UPLOAD_BUCKET_NAME"/public
echo "Anonymous download-доступ на '$AWS_S3_UPLOAD_BUCKET_NAME/public' выставлен"
