#!/usr/bin/env bash
set -eu
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cd "$(dirname "$0")/.."

EMAIL="$1"
USERNAME="$2"
PASSWORD="$3"
CONFIG_FILE="dex/config.yaml"

if grep -q "email: \"$EMAIL\"" "$CONFIG_FILE"; then
    echo "Ошибка: Пользователь с email '$EMAIL' уже существует!"
    exit 1
fi

echo "Генерация хэша и UUID..."
HASH=$(sh scripts/gen-bcrypt.sh "$PASSWORD")
UUID=$(cat /proc/sys/kernel/random/uuid)

echo "Добавление пользователя в конфигурацию Dex..."
sed -i "/^staticPasswords:/a \\
  - email: \"$EMAIL\"\\
    hash: \"$HASH\"\\
    username: \"$USERNAME\"\\
    userID: \"$UUID\"" "$CONFIG_FILE"

echo "Перезапуск сервиса авторизации..."
docker compose restart dex
echo "Готово! Пользователь $USERNAME ($EMAIL) успешно добавлен."