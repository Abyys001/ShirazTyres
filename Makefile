.PHONY: up down logs migrate seed test lint schema types shell

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f backend worker

migrate:
	docker compose exec backend python manage.py makemigrations && docker compose exec backend python manage.py migrate

seed:
	docker compose exec backend python manage.py seed_demo

test:
	docker compose exec backend pytest

lint:
	docker compose exec backend ruff check .

schema:
	docker compose exec backend python manage.py spectacular --file /app/openapi.yaml

types: schema
	cd panel && npm run generate:types

shell:
	docker compose exec backend python manage.py shell
