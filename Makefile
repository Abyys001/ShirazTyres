.PHONY: up up-dev down logs migrate makemigrations seed test test-demo lint schema types shell psql websocket-check emulator waydroid web-apps

# Boot the Pixel_Tyres emulator and run BOTH Flutter apps in debug mode
# (hot reload enabled) inside tmux. Press r / R / q in each pane.
emulator:
	scripts/run_emulator.sh

# Same, but against a running Waydroid container (see scripts/run_waydroid.sh).
waydroid:
	scripts/run_waydroid.sh

# Build both Flutter apps for the web into panel/public/apps, so each one opens
# in a browser tab from the panel's Apps page. No emulator, no handset.
web-apps:
	scripts/build_web_apps.sh

up:
	docker compose up -d --build

# The same stack with `next dev` and a bind mount behind the panel and the
# website, for working on either of them. Slower to load by a wide margin —
# that is what it costs to have a save show up without a rebuild.
up-dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build

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

# The whole call-out across all three surfaces, against the running stack: a
# customer raises a job, the panel and the technician see it live, the job is
# taken, driven to completion and invoiced. Run this before a demo.
# Needs `make seed`, and the technician on 07700900301 not already on a job.
test-demo:
	node scripts/demo_check.mjs

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
