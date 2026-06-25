#!/usr/bin/env bash
set -eu
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cd "$(dirname "$0")/.."

EMAIL="$1"
CONFIG_FILE="dex/config.yaml"

if ! grep -q "email: \"$EMAIL\"" "$CONFIG_FILE"; then
    echo "Ошибка: Пользователь '$EMAIL' не найден!"
    exit 1
fi

read -p "Вы точно хотите удалить $EMAIL? (y/N): " confirm
if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] && "$confirm" != "д" && "$confirm" != "Д" ]]; then
    echo "Отмена."
    exit 0
fi

echo "Удаление пользователя из конфигурации..."
sed -i "/^[[:space:]]*- email: \"$EMAIL\"/,+3d" "$CONFIG_FILE"

echo "Перезапуск сервиса авторизации..."
docker compose restart dex
echo "Готово! Пользователь $EMAIL успешно удален."