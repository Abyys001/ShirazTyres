# ShirazTyres

Emergency tyre dispatch for London. One API, four surfaces.

| Surface | Who uses it | Stack |
|---|---|---|
| `website/` | customers, on the web | Next.js 15 (App Router) + React 19 + TanStack Query + Tailwind |
| `mobile_customer/` | customers, on Android and iOS | Flutter + Riverpod + dio + go_router |
| `panel/` | the owner and the office | Next.js 15 + Leaflet |
| `mobile/` | ShirazTyres technicians | Flutter, restricted distribution |
| `web-widget/` | the existing marketing site | vanilla JS, shadow DOM, no build step |
| `backend/` | all of the above | Django 5 + DRF + Channels, PostgreSQL 16, Redis, Celery |

**Terminology matters here and is used consistently throughout the code.** A
**customer** is the stranded motorist. A **driver** is a ShirazTyres technician —
an employee. The customer's broken-down car and the technician's service van are
separate entities that never share a table.

A customer reports a puncture from the website or the app; the plate is resolved
to a vehicle and a tyre size which the customer must explicitly confirm; the job
is offered to technicians ranked by real travel time; the customer follows a
live ETA while the technician's position stays inside the office.

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
| Owner panel | <http://localhost:3000> |
| Customer website | <http://localhost:3001> |

Out of the box everything external is mocked — `SMS_PROVIDER=mock`,
`PUSH_PROVIDER=mock`, `VEHICLE_LOOKUP_MOCK=1`, `GOOGLE_OAUTH_MOCK=1`,
`ROUTING_PROVIDER=mock` — so the whole flow runs with no API keys and no spend.
Mock OTPs come back in the response as `debug_code`.

Both Flutter apps point at the emulator's host by default. The default
workflow boots the Pixel_Tyres emulator and runs **both** apps in debug mode
with hot reload enabled, in a tmux session:

```bash
make emulator     # boot emulator + driver & customer apps, hot reload on
```

In each tmux pane (left = driver, right = customer): `r` hot reloads, `R`
hot-restarts, `q` quits. Both apps install on the single `Pixel_Tyres` AVD,
which persists installed apps across reboots.

If you'd rather drive them by hand:

```bash
cd mobile          && flutter run -d emulator-5554   # technician app
cd mobile_customer && flutter run -d emulator-5554   # customer app
```

## Make targets

| Target | Does |
|---|---|
| `make up` / `make down` | bring the stack up / down |
| `make logs` | follow backend, worker and beat |
| `make migrate` | apply migrations |
| `make seed` | demo owner, office staff, service area, drivers, customers, jobs |
| `make emulator` | boot Pixel_Tyres AVD + run both Flutter apps (debug, hot reload) |
| `make test` | backend pytest suite in Docker |
| `make test-local` | the same suite on SQLite, no Docker needed |
| `make lint` | ruff |
| `make schema` | regenerate `backend/openapi.yaml` |
| `make types` | schema, then TypeScript types for the panel and the website |

## How dispatch works

Two modes, both configurable in the panel without a deploy:

- **Automatic assignment** — the job goes to the best-ranked technician.
- **Driver selection** — it is offered to the nearest *N* at once, first to
  accept wins.

Three rules shape the engine:

1. **Candidates are ranked by routing travel time, never straight-line
   distance.** In London the nearest van by crow-flight is regularly not the
   first to arrive.
2. **Rejection is a first-class answer in both modes.** It escalates
   immediately rather than waiting out the timeout, and a technician who
   rejected a job is never offered it again.
3. **Silence escalates too.** Every offer has a deadline; when it passes the job
   moves on, and after the configured number of rounds it is marked `unclaimed`
   and the owner is alerted. A job stuck with nobody waiting on it is the worst
   failure this system has, so a Celery beat sweep catches any timer lost to a
   worker restart.

## The two lookup APIs

DVLA's Vehicle Enquiry Service gives make, model, colour, MOT and tax — but
**not** tyre size, because DVLA does not hold it. Tyre size comes from a separate
commercial fitment API. The two are fetched independently and cached by plate, so
a tyre-API outage degrades the record instead of failing the call-out. Anything a
human confirms is never overwritten by a later automated lookup.

Both providers have mock implementations. Plates beginning `XX` simulate a DVLA
miss, `YY` a tyre-data miss.

Because trims of the same model take different sizes, the customer must confirm
the looked-up specification before the request can be submitted. If they decline,
they are shown a responsibility notice, must acknowledge it, and only then may
enter their own values — and the job keeps **both** figures, so a technician who
arrives with the wrong tyre can be shown exactly what was displayed and what was
entered.

## What the customer never sees

The customer sees their technician's first name, photograph, and the van's make,
model, colour and plate — and a live ETA. They do not see the technician on a
map. The ETA is recalculated on the backend each time the van moves and only the
figure is sent, which keeps an employee's live position off customer surfaces.
Insurance numbers, document scans and personal phone numbers never leave the
office. This boundary is enforced by omission in the serializers and in
`apps/realtime/publish.py`, and is covered by tests.

## Authentication

Three audiences, one token format. Access tokens carry a `scope` claim
(`staff`, `customer`, `driver`) and DRF tries a scoped authenticator per
audience, so a token for one can never reach another's endpoints.

- **Customers** sign in with Google or phone OTP. Both routes resolve to the same
  account and the same job history.
- **Technicians** sign in with phone OTP, and receive no work until an
  administrator has approved their documents.
- **Staff** sign in with email and password. The panel and the website keep both
  tokens in httpOnly cookies and proxy every call server-side, so the browser
  never holds a JWT — except for the one short-lived token a WebSocket handshake
  needs, which cannot carry a header.

## Repo layout

```
backend/           Django project (config/) + apps/
                     accounts, customers and staff, three token scopes
                     drivers, vehicles (customer cars), geo (service areas)
                     bookings (jobs), dispatch, billing, notifications
                     configuration (the settings catalogue), realtime (WebSocket)
panel/             Next.js owner panel
website/           Next.js customer site
mobile/            Flutter technician app
mobile_customer/   Flutter customer app
web-widget/        embeddable entry point for the existing marketing site
docs/              API surface, data model, deployment
```

## Docs

- [`docs/api.md`](docs/api.md) — endpoint reference and the three auth flows
- [`docs/data-model.md`](docs/data-model.md) — entities, the status machine, dispatch
- [`docs/deployment.md`](docs/deployment.md) — going live, real providers, GDPR
- [`Project_view.md`](Project_view.md) — the version 2.0 specification this implements
