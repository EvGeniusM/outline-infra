# Outline IaC

Self-hosted [Outline](https://github.com/outline/outline) за reverse-proxy Caddy, со своим OIDC-провайдером (Dex) и S3-совместимым хранилищем (MinIO) — поднимается одной командой через Docker Compose.

## Архитектура

| Сервис    | Образ                       | Роль                                    | Наружу                  |
|-----------|------------------------------|------------------------------------------|--------------------------|
| caddy     | `caddy:2`                    | reverse proxy, маршрутизация по доменам  | 80 (443 в проде)         |
| outline   | `outlinewiki/outline:0.82.0` | сама вики                                | только через caddy       |
| postgres  | `postgres:16`                | основная БД                              | нет                       |
| redis     | `redis:7`                    | очереди/кэш Outline                      | нет                       |
| minio     | `minio/minio`                | S3-хранилище вложений и аватаров         | только через caddy + 9001 (консоль) |
| minio-init| `minio/mc`                   | one-shot: создаёт бакет и его public-policy | —                      |
| dex       | `dexidp/dex`                 | OIDC-провайдер (тестовый статический юзер) | только через caddy     |

Caddy раздаёт три домена и резолвит их и для браузера, и для контейнеров между собой (через `networks.default.aliases`, т.к. `outline` и `dex` ходят друг к другу по тем же хостам, что видит браузер):
- `app.*`   → `outline:3000`
- `auth.*`  → `dex:5556`
- `files.*` → `minio:9000` (S3 API; нужен браузеру напрямую — см. «Конфигурация хранилища» ниже)

## Требования

- Docker Engine + Compose plugin (Docker Desktop с WSL2 на Windows).
- Git Bash (для `scripts/*.sh`) и `openssl` в PATH.
- Свободный порт 80 (`netstat -ano | findstr :80` / `ss -ltnp | grep :80`).

## Быстрый старт (локально)

```bash
# 1. Сгенерировать секреты и .env
sh scripts/gen-secrets.sh           # или: make init

# 2. Поднять стек
docker compose up -d                # или: make up

# 3. Открыть в браузере
#    http://app.localhost
#    Вход: admin@example.com / password
```

Точки входа:
- Outline: http://app.localhost
- OIDC (Dex): http://auth.localhost
- minio S3 API: http://files.localhost
- minio консоль: http://localhost:9001

## Команды

| Команда      | Что делает                                              |
|--------------|-----------------------------------------------------------|
| `make init`  | генерирует `.env` из `.env.example` (`SECRET_KEY`/`UTILS_SECRET`) |
| `make up`    | `docker compose up -d`                                     |
| `make down`  | `docker compose down` — контейнеры и сеть, volume'ы целы   |
| `make reset` | `docker compose down -v` — полный снос вместе с данными    |
| `make logs`  | хвост логов всех сервисов                                  |
| `make ps`    | статус контейнеров                                          |

## Конфигурация

Все переменные и дефолты — в `.env.example`. Основные группы:

- **General** — `URL`, `FORCE_HTTPS`, `SECRET_KEY`/`UTILS_SECRET` (генерируются `gen-secrets.sh`).
- **Postgres / Redis** — стандартные параметры подключения, без выхода наружу.
- **S3 (minio)** — `AWS_S3_UPLOAD_BUCKET_URL`, `AWS_S3_ACL`, `MINIO_API_CORS_ALLOW_ORIGIN`.
- **OIDC (Dex)** — `OIDC_AUTH_URI`/`OIDC_TOKEN_URI`/`OIDC_USERINFO_URI`, должны указывать на `auth.*` и совпадать с `dex/config.yaml`.

### Конфигурация хранилища (важно)

Outline хранит вложения двумя разными способами:
- вложения в документах — приватные (`acl=private`, ключ `uploads/...`), браузер получает их через подписанный `/api/attachments.redirect?id=...`, который Outline генерирует на каждый запрос;
- аватары пользователей и лого команды (вложения без привязки к документу) — `acl=public-read`, ключ `public/...`, и `avatarUrl` хранится как **прямая** ссылка на S3, которую браузер запрашивает без участия Outline.

Поэтому бакету нужна anonymous-policy именно на префикс `public/` — её выставляет `scripts/minio-init.sh` (`mc anonymous set download local/<bucket>/public`) при каждом старте. Без неё аватарки молча не отображаются после сохранения (попытка сохранить проходит на бэкенде успешно, но картинка не грузится в браузере — 403 от MinIO), хотя вставка картинок в документы продолжает работать.

## Подводные камни

- **Порт 80 занят** → менять во всех местах сразу (publish, `URL`, `Caddyfile`).
- **CRLF** ломает конфиги в контейнерах — `.gitattributes` форсит LF.
- **Тег Outline пинуется** — не использовать `latest`.
- `*.localhost` внутри контейнеров работает только через алиасы Caddy.
- Не путать «группу» (Outline Groups) с аватаром пользователя/команды: у групп в этой версии Outline нет загружаемого изображения вообще (только сгенерированный цветной кружок с инициалами) — менять там можно только название.

## Смена пароля тестового юзера

```bash
sh scripts/gen-bcrypt.sh 'НОВЫЙ_ПАРОЛЬ'   # вставить хэш в dex/config.yaml -> hash
docker compose restart dex
```

## Деплой на VM (прод)

Это локальный концепт (`*.localhost`, HTTP, тестовый юзер в Dex) — при выезде на настоящую VM нужно осознанно поменять домены, включить TLS и ротировать секреты. Ниже — чек-лист для Ubuntu 24.04 с реальным доменом и Caddy auto-HTTPS.

### 0. DNS

Три A-записи на публичный IP VM: `app.<domain>`, `auth.<domain>`, `files.<domain>`. `files.*` обязателен — браузер ходит туда напрямую за аватарками/файлами (см. «Конфигурация хранилища»).

**Если можно создать только одну A-запись (без поддоменов).** Поддомены не обязательны — Caddy получает сертификат на доменное имя независимо от того, какой порт слушает конкретный site-block. Поэтому можно развести все три сервиса на одном `<domain>` по разным портам, не трогая DNS вообще:

```caddyfile
<domain> {
	reverse_proxy outline:3000
}

<domain>:8443 {
	reverse_proxy dex:5556
}

<domain>:9443 {
	reverse_proxy minio:9000
}
```

И соответственно: `OIDC_AUTH_URI=https://<domain>:8443/auth` (+ `TOKEN_URI`/`USERINFO_URI`), `AWS_S3_UPLOAD_BUCKET_URL=https://<domain>:9443`, `issuer: https://<domain>:8443` и `redirectURIs: [https://<domain>/auth/oidc.callback]` в `dex/config.yaml`, `MINIO_API_CORS_ALLOW_ORIGIN=https://<domain>` (без порта — приложение всё ещё на 443). В `docker-compose.yml` у `caddy` нужно опубликовать и `8443:8443`, `9443:9443`; в firewall (шаг 2) — открыть те же порты. Порт 80 всё равно должен быть открыт: по нему идёт ACME HTTP-01 challenge для выпуска сертификата.

Если позже появится доступ хотя бы к одной дополнительной записи — проще завести `*.<domain> -> IP` (wildcard) и вернуться к варианту с поддоменами из остальных шагов ниже.

### 1. Базовая подготовка VM

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER   # перелогиниться
sudo apt install -y git
```

### 2. Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

**Порт 9001 (minio-консоль) наружу не открывать.** Сейчас он опубликован напрямую на хост без какой-либо авторизации перед ним (Caddy его не проксирует). Для прода — убрать `ports: ["9001:9001"]` из `docker-compose.yml` и ходить через `ssh -L 9001:localhost:9001 user@vm`, либо ограничить ufw по source IP.

### 3. Код на VM

```bash
git clone https://github.com/EvGeniusM/outline-infra.git
cd outline-infra
git checkout feat/outline-iac   # или ветка, в которую смержили
```

### 4. Секреты — не копировать локальный `.env`

```bash
make init
```

`gen-secrets.sh` генерирует только `SECRET_KEY`/`UTILS_SECRET`. Остальные плейсхолдеры из `.env.example` (`POSTGRES_PASSWORD`, `MINIO_ROOT_PASSWORD`/`AWS_SECRET_ACCESS_KEY`, `OIDC_CLIENT_SECRET`) нужно руками заменить на новые случайные значения (`openssl rand -hex 24`) — не те, что использовались локально.

### 5. `.env` под домен

```
URL=https://app.<domain>
FORCE_HTTPS=true
AWS_S3_UPLOAD_BUCKET_URL=https://files.<domain>
MINIO_API_CORS_ALLOW_ORIGIN=https://app.<domain>
OIDC_AUTH_URI=https://auth.<domain>/auth
OIDC_TOKEN_URI=https://auth.<domain>/token
OIDC_USERINFO_URI=https://auth.<domain>/userinfo
```

### 6. `dex/config.yaml`

```yaml
issuer: https://auth.<domain>
staticClients:
  - id: outline
    redirectURIs:
      - https://app.<domain>/auth/oidc.callback
```

Плюс сразу сменить тестовый пароль (см. «Смена пароля тестового юзера») — нельзя оставлять дефолтный хэш из репозитория при выходе в публичный домен.

### 7. `Caddyfile` и `docker-compose.yml`

- Убрать `auto_https off` (оставить `admin off`).
- Сайт-блоки — без `http://`, с реальными доменами (`app.<domain>`, `auth.<domain>`, `files.<domain>`); Caddy сам получит сертификаты Let's Encrypt по HTTP-01.
- В `networks.default.aliases` для `caddy` — те же реальные домены вместо `*.localhost`.
- В `ports` для `caddy` добавить `"443:443"`.

### 8. Запуск и проверка

```bash
make up
docker compose logs -f caddy   # сертификаты выданы без ошибок
docker compose ps              # все healthy
```

Зайти на `https://app.<domain>`, пройти OIDC-логин и проверить загрузку аватарки — лучший сквозной тест, что домены/CORS/S3-policy согласованы.

### После запуска

Бэкап `postgres-data` (`pg_dump`) и `minio-data` (`mc mirror`) в этом репозитории не настроен — данные живут только в docker volume на одной VM. Если стенд не одноразовый, это первое, что нужно добавить отдельно.
