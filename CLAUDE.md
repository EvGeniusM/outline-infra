# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Что это за репозиторий

Чистый IaC-стек на Docker Compose: self-hosted [Outline](https://github.com/outline/outline)
за reverse-proxy Caddy, со своим OIDC-провайдером (Dex) и S3-совместимым
хранилищем (MinIO). Никакого прикладного кода (Node/TS/etc.) здесь нет —
только `docker-compose.yml`, конфиги сервисов и shell-скрипты. Соответственно
нет ни build, ни lint, ни unit-тестов — «тест» этого репозитория — это
успешный подъём стека и сквозная проверка login → upload (см. «Проверка
после изменений» ниже).

## Команды

```bash
make init   # = sh scripts/gen-secrets.sh — создаёт .env из .env.example, генерирует SECRET_KEY/UTILS_SECRET
make up     # = docker compose up -d
make down   # = docker compose down        (volume'ы целы)
make reset  # = docker compose down -v     (полный снос вместе с данными)
make logs   # = docker compose logs -f
make ps     # = docker compose ps
```

На Windows `make` не из коробки — все команды выше имеют документированный
сырой docker-compose эквивалент в README; используй его, если `make`
недоступен.

Смена пароля тестового юзера Dex:
```bash
sh scripts/gen-bcrypt.sh 'НОВЫЙ_ПАРОЛЬ'   # bcrypt-хэш → вставить в dex/config.yaml -> staticPasswords[0].hash
docker compose restart dex
```

Требуют Git Bash + `openssl` в PATH (скрипты в `scripts/*.sh` написаны под POSIX sh).

### Проверка после изменений

Нет автотестов — после правок в compose/конфигах руками прогнать acceptance-чеклист:
1. `make up` → все контейнеры `healthy`/`exited (0)` для `minio-init`.
2. `http://app.localhost` редиректит на Dex, логин `admin@example.com` / `password` проходит.
3. Создание документа + загрузка картинки в него (проверяет MinIO presigned-PUT + CORS).
4. Загрузка/смена аватара пользователя (отдельный путь от п.3, см. «Конфигурация хранилища» ниже — легко сломать одно не заметив другое).
5. Realtime-правки видны без перезагрузки (WebSocket через Caddy).
6. `make down && make up` — документы и файлы на месте (persistence postgres+minio).

## Архитектура

### Топология сервисов

| Сервис     | Образ                       | Роль                                       |
|------------|-----------------------------|---------------------------------------------|
| caddy      | `caddy:2`                   | единая точка входа, маршрутизация по доменам |
| outline    | `outlinewiki/outline:0.82.0`| сама вики (тег **пинуется**, не `latest`)   |
| postgres   | `postgres:16`                | основная БД                                |
| redis      | `redis:7`                    | очереди/кэш/websockets Outline             |
| minio      | `minio/minio`                | S3-хранилище вложений и аватаров           |
| minio-init | `minio/mc`                   | one-shot: создаёт бакет + public-policy + завершается |
| dex        | `dexidp/dex`                 | OIDC-провайдер, один статический test-юзер |

Outline не умеет логиниться по логину/паролю и не поддерживает GitHub OAuth
(не OIDC-совместим) — поэтому в стеке свой Dex как generic-OIDC заглушка.
Переезд на реальный SSO — это замена блока `OIDC_*` переменных в `.env`,
топология стека не меняется.

### Ключевое архитектурное решение: единые URL через `*.localhost`

OIDC issuer и presigned-ссылки S3 должны быть **байт-в-байт одинаковыми** и
для браузера, и для контейнера `outline` — иначе либо ломается логин (issuer
mismatch), либо загрузка файлов. Решение — Caddy как единственная точка
входа на host-порту 80, с маршрутизацией по поддоменам (`caddy/Caddyfile`):
`app.localhost` → outline, `auth.localhost` → dex, `files.localhost` → minio.

Это работает с обеих сторон по разным механизмам:
- **Браузер** резолвит `*.localhost` в `127.0.0.1` автоматически (без правки hosts).
- **Контейнеры** такой магии не имеют — поэтому на сервисе `caddy` в
  `docker-compose.yml` объявлены `networks.default.aliases` с теми же тремя
  именами. Контейнер `outline` резолвит `auth.localhost`/`files.localhost` в
  сам Caddy (не напрямую в dex/minio), Caddy уже проксирует дальше.

Инвариант: Caddy обязан слушать host-порт **80**. Если порт занят и его
меняют — нужно поменять одновременно в трёх местах: `ports` в
docker-compose.yml, `URL`/`AWS_S3_UPLOAD_BUCKET_URL` в `.env`, домены в
`Caddyfile` — иначе браузерная и серверная стороны разойдутся.

### Конфигурация хранилища: два разных пути загрузки в один бакет

Outline кладёт файлы в MinIO двумя несовместимыми способами:
- **Вложения в документах** — `acl=private`, ключ `uploads/...`; браузер
  получает их через подписанный `/api/attachments.redirect?id=...`,
  который Outline генерирует на каждый запрос (S3 credentials не светятся).
- **Аватары пользователей/лого команды** — `acl=public-read`, ключ
  `public/...`; `avatarUrl` хранится как прямая ссылка на S3/MinIO, браузер
  обращается к ней без участия Outline.

Поэтому `scripts/minio-init.sh` при каждом старте выставляет анонимную
download-policy именно на префикс `public/` (`mc anonymous set download
local/<bucket>/public`). Без этого аватарки **молча** не отображаются после
сохранения — сохранение проходит успешно на бэкенде, но картинка не грузится
в браузере (403 от MinIO), при этом вставка картинок в документы продолжает
работать как ни в чём не бывало. Эти два пути легко спутать при дебаге.

Группы Outline (Outline Groups) в этой версии вообще не имеют загружаемого
изображения — только сгенерированный цветной кружок с инициалами; путать с
аватаром пользователя/команды не нужно.

### Порядок запуска / health-гейтинг

`outline` стартует только когда `postgres`+`redis` healthy и `minio-init`
завершился успешно (`service_completed_successfully`) — это гарантирует, что
бакет и его `public/`-policy уже существуют до того, как Outline попытается
писать в S3. Миграции БД Outline прогоняет сам при старте, отдельного шага
для них в стеке нет.

## Деплой за пределы локалки

Это локальный концепт (`*.localhost`, HTTP, тестовый юзер в Dex). README
содержит подробный чек-лист переноса на реальную VM (домены, TLS,
ротация всех секретов кроме `SECRET_KEY`/`UTILS_SECRET` — те генерирует
`gen-secrets.sh`, остальные — `POSTGRES_PASSWORD`, `MINIO_ROOT_PASSWORD`/
`AWS_SECRET_ACCESS_KEY`, `OIDC_CLIENT_SECRET` — руками).

Backup/DR: `make backup`/`make restore ARCHIVE=...` (`scripts/backup.sh`/`restore.sh`) —
дамп postgres + mc mirror minio в один `backups/<TS>.tar.gz`, ротация 7 последних,
по умолчанию по cron ежедневно. Хранится локально на той же VM — не защищает от потери
самой VM, только от порчи данных. Обе утилиты гоняют one-off `minio/mc` контейнер с
`--user $(id -u):$(id -g)` — без этого файлы в bind-mount уходят от root и `rm`/ротация
ломаются правами.

## Windows-специфика

- `.gitattributes` форсит `eol=lf` для `*.sh`, `Caddyfile`, `*.yaml`/`*.yml` —
  CRLF ломает эти конфиги внутри Linux-контейнеров.
- Нужен Docker Desktop с WSL2-бэкендом.
- `make` отсутствует из коробки — см. сырые docker-compose команды в README,
  они первичны для Windows-разработки.
