SHELL := /bin/bash

.PHONY: init up down logs ps reset backup restore add-user del-user

init:
	sh scripts/gen-secrets.sh

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

ps:
	docker compose ps

reset:
	docker compose down -v

backup:
	sh scripts/backup.sh

restore:
	sh scripts/restore.sh $(ARCHIVE)

add-user:
	@read -p "Введите Email нового пользователя: " email; \
	read -p "Введите Имя (например, Ivan Ivanov): " name; \
	read -s -p "Введите Пароль (ввод скрыт): " pass; echo ""; \
	sh scripts/add-user.sh "$$email" "$$name" "$$pass"

del-user:
	@read -p "Введите Email пользователя для удаления: " email; \
	sh scripts/del-user.sh "$$email"