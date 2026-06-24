#!/usr/bin/env sh
set -eu

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Создан .env из .env.example"
fi

gen() { openssl rand -hex 32; }

# Подставить SECRET_KEY/UTILS_SECRET, если они ещё плейсхолдеры
for var in SECRET_KEY UTILS_SECRET; do
  if grep -q "^${var}=__GENERATE__" .env; then
    val=$(gen)
    # sed -i на разных платформах; используем временный файл для переносимости
    sed "s|^${var}=__GENERATE__|${var}=${val}|" .env > .env.tmp && mv .env.tmp .env
    echo "Сгенерирован ${var}"
  fi
done

echo "Готово. Проверьте .env."
