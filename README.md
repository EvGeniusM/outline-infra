# Outline IaC (локальный концепт)

Стек: Outline + Postgres + Redis + minio + Dex (OIDC) за reverse proxy Caddy.

## Требования
- Docker Desktop с WSL2 (Windows).
- Git Bash (для `scripts/*.sh`) и `openssl` в PATH.
- Свободный **порт 80** (`netstat -ano | findstr :80`).

## Запуск
```bash
# 1. Сгенерировать секреты и .env
sh scripts/gen-secrets.sh           # или: make init

# 2. Поднять стек
docker compose up -d                # или: make up

# 3. Открыть в браузере
#    http://app.localhost
#    Вход: admin@example.com / password
```

Остановка: `docker compose down` (`make down`).
Полный сброс с данными: `docker compose down -v` (`make reset`).

## Точки входа
- Outline:        http://app.localhost
- OIDC (Dex):     http://auth.localhost
- minio S3 API:   http://files.localhost
- minio консоль:  http://localhost:9001

## Подводные камни
- **Порт 80 занят** → менять во всех местах сразу (publish, URL, Caddyfile).
- **CRLF** ломает конфиги в контейнерах — `.gitattributes` форсит LF.
- **Тег Outline пинуется** — не использовать `latest`.
- `*.localhost` внутри контейнеров работает только через алиасы Caddy.

## Смена пароля тестового юзера
```bash
sh scripts/gen-bcrypt.sh 'НОВЫЙ_ПАРОЛЬ'   # вставить хэш в dex/config.yaml -> hash
docker compose restart dex
```

## Переезд в облако
Сменить домены `*.localhost` на реальные, включить TLS в Caddyfile,
заменить Dex на реальный OIDC-провайдер, вынести секреты из `.env`.
