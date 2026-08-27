# ShirazTyres

Emergency tyre call-out platform. One API, three front doors:

| Surface | Who uses it | Stack |
|---|---|---|
| `web-widget/` | drivers on the existing website | vanilla JS, shadow DOM, no build step |
| `panel/` | the shop owner and fitters | Next.js 15 (App Router) + React 19 + TanStack Query + Tailwind |
| `mobile/` | returning drivers | Flutter + Riverpod + dio + go_router |
| `backend/` | all of the above | Django 5 + DRF, PostgreSQL 16, Redis, Celery |

A driver reports a puncture from any of the three; the plate is resolved to a
vehicle and a tyre size; the shop is notified by push, SMS and email within
seconds; the job moves through a status machine that every surface can watch.

## Quick start

```bash
cp .env.example .env
make up          # docker compose up -d --build
make migrate
make seed        # demo data: owner@shiraztyres.co.uk / shiraz1234
```

| | |
|---|---|
| API | <http://localhost:8000/api/v1> |
| API docs (Swagger) | <http://localhost:8000/api/docs/> |
| Django admin | <http://localhost:8000/admin/> |
| Admin panel | <http://localhost:3000> |

Out of the box everything external is mocked — `SMS_PROVIDER=mock`,
`PUSH_PROVIDER=mock`, `VEHICLE_LOOKUP_MOCK=1` — so the whole flow runs with no
API keys and no spend. Mock OTPs come back in the response as `debug_code`.

## Make targets

| Target | Does |
|---|---|
| `make up` / `make down` | bring the stack up / down |
| `make logs` | follow backend + worker |
| `make migrate` | makemigrations + migrate |
| `make seed` | demo owner, fitter, drivers, vehicles, bookings |
| `make test` | backend pytest suite |
| `make lint` | ruff |
| `make schema` | regenerate `backend/openapi.yaml` |
| `make types` | schema, then panel TypeScript types from it |

## The two lookup APIs

DVLA's Vehicle Enquiry Service gives make, model, colour, MOT and tax — but
**not** tyre size, because DVLA does not hold it. Tyre size comes from a
separate commercial fitment API. The two are fetched independently and cached
with their own TTLs, so a tyre-API outage degrades the record instead of
failing the call-out. Anything a human confirms (`tyre_source` = `staff` or
`driver`) is never overwritten by a later automated lookup.

Both providers have mock implementations. Plates beginning `XX` simulate a DVLA
miss, `YY` a tyre-data miss.

## Authentication

Two audiences, one token format. Access tokens carry a `scope` claim
(`staff` or `driver`) and DRF tries a scoped authenticator per audience, so a
driver token can never reach a panel endpoint and vice versa.

- **Drivers** sign in with phone + OTP. Codes are hashed at rest, single-use,
  TTL-bound, attempt-capped and rate-limited. Drivers are *not* Django users.
- **Staff** sign in with email + password. The panel keeps both tokens in
  httpOnly cookies and proxies every call server-side, so the browser never
  holds a JWT.

## Repo layout

```
backend/     Django project (config/) + apps/{accounts,vehicles,bookings,notifications}
panel/       Next.js admin panel
mobile/      Flutter driver app
web-widget/  embeddable call-out widget for the existing site
docs/        API surface, data model, deployment
```

Each front end has its own README with setup specific to it.

## Docs

- [`docs/api.md`](docs/api.md) — endpoint reference and the two auth flows
- [`docs/data-model.md`](docs/data-model.md) — entities and the status machine
- [`docs/deployment.md`](docs/deployment.md) — going live, real providers, GDPR
