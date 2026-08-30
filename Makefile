.PHONY: up down logs migrate makemigrations seed test lint schema types shell psql websocket-check emulator

# Boot the Pixel_Tyres emulator and run BOTH Flutter apps in debug mode
# (hot reload enabled) inside tmux. Press r / R / q in each pane.
emulator:
	scripts/run_emulator.sh

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f backend worker beat

makemigrations:
	docker compose exec backend python manage.py makemigrations

migrate:
	docker compose exec backend python manage.py migrate

seed:
	docker compose exec backend python manage.py seed_demo

test:
	docker compose exec backend pytest

# The suite runs without Postgres or Redis; useful before the stack is even up.
test-local:
	cd backend && USE_SQLITE=1 ./.venv/bin/pytest

lint:
	docker compose exec backend ruff check .

schema:
	docker compose exec backend python manage.py spectacular --file /app/openapi.yaml

types: schema
	cd panel && npm run generate:types
	cd website && npm run generate:types

shell:
	docker compose exec backend python manage.py shell

psql:
	docker compose exec db psql -U $${POSTGRES_USER:-shiraztyres} -d $${POSTGRES_DB:-shiraztyres}
