#!/usr/bin/env sh
set -eu

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Создан .env из .env.example"
fi

gen() { openssl rand -hex 32; }

for var in SECRET_KEY UTILS_SECRET PLANE_SECRET_KEY LIVE_SERVER_SECRET_KEY RABBITMQ_PASSWORD; do
  if grep -q "^${var}=__GENERATE__" .env; then
    val=$(gen)
    sed "s|^${var}=__GENERATE__|${var}=${val}|" .env > .env.tmp && mv .env.tmp .env
    echo "Сгенерирован ${var}"
  fi
done

echo "Готово. Проверьте .env."
