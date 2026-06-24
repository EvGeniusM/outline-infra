.PHONY: init up down logs reset ps

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
