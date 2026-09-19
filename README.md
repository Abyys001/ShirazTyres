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

Set `BACKEND_HOST_PORT`, `PANEL_HOST_PORT` and `WEBSITE_HOST_PORT` if something
on your machine already holds those ports — and move `NEXT_PUBLIC_API_BASE_URL`,
`NEXT_PUBLIC_WS_BASE_URL`, `CORS_ALLOWED_ORIGINS` and `CSRF_TRUSTED_ORIGINS` with
them, because the browser talks to the published port and the API checks the
origin it came from.

Out of the box everything external is mocked — `SMS_PROVIDER=mock`,
`PUSH_PROVIDER=mock`, `VEHICLE_LOOKUP_MOCK=1`, `GOOGLE_OAUTH_MOCK=1`,
`ROUTING_PROVIDER=mock`, `STRIPE_MODE=mock` — so the whole flow runs with no API
keys and no spend. **Settings → System** shows which are still stubbed, because
everything mocked looks identical to everything working.
Mock OTPs come back in the response as `debug_code`, and both apps surface that
code on screen rather than making you dig it out of a log.

### Signing in

| Surface | Credential |
|---|---|
| Owner panel | `owner@shiraztyres.co.uk` / `shiraz1234` |
| Driver app | `07700900301` … `07700900304` approved, `07700900305` pending |
| Customer app | `07700900101` … `07700900103`, or any number to register |

Each sign-in screen lists these in a **Development sign-in** panel — one tap
fills the field, and the verification code appears above it. The panel is gated
on a debug build talking to a local API, so it cannot reach a release.
Full detail, including Google sign-in without OAuth credentials and what to do
when a sign-in fails, is in [`docs/dev-logins.md`](docs/dev-logins.md).

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

### Both apps in a browser tab

An emulator is a five-minute detour when the question is only "does the offer
land?". Both apps also build for the web, into the panel's own static files:

```bash
make web-apps    # scripts/build_web_apps.sh
```

The panel then lists every surface — technician app, customer app and the
customer website at <https://shiraztyres.co.uk/> — on **Apps**, each with an
Open button and the numbers to sign in with. The API address is baked into
these builds, and is taken from `NEXT_PUBLIC_API_BASE_URL` in `.env`, so a
stack published on a server produces apps that reach that server rather than
whoever opens them. The builds are served same-origin
by the panel, at
<http://localhost:3010/apps/driver/index.html> and
<http://localhost:3010/apps/customer/index.html>,
and they talk to the same API as everything else. The development sign-in panel
is on, because a release build would otherwise hide it (`DEV_SIGN_IN=false`
turns it off for a demo).

**It is a testing and demo surface, not a shipping target.** A browser tab has
no push notifications and no background location, and on a desktop no useful
camera — so offers arrive on the socket rather than as a notification, and the
technician's position only moves while the tab is in front. Everything else —
the whole call-out, live — works. The Apps entry is development-only and is not
in a production panel bundle.

## Make targets

| Target | Does |
|---|---|
| `make up` / `make down` | bring the stack up / down |
| `make logs` | follow backend, worker and beat |
| `make migrate` | apply migrations |
| `make seed` | demo owner, office staff, service area, drivers, customers, jobs |
| `make emulator` | boot Pixel_Tyres AVD + run both Flutter apps (debug, hot reload) |
| `make web-apps` | build both Flutter apps for the web into the panel's **Apps** page |
| `make test` | backend pytest suite in Docker |
| `make test-local` | the same suite on SQLite, no Docker needed |
| `make test-demo` | the whole call-out across all three surfaces, live, against the running stack |
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

Underneath the rounds sits **the open board** — `GET /driver/jobs/available`, the
first section of the technician app's shift screen. An offer is a question with a
deadline and disappears when the round moves on; the board does not. Every
call-out still waiting for somebody stays listed there, and a technician can take
one with `POST /driver/jobs/{id}/claim`. A claim is awarded exactly as an
accepted offer is — the round is written down, the other offers are withdrawn and
the ETA is set — so the audit trail does not care which direction the work came
from. A driver who rejected a job is not shown it again; one who merely missed
the round is, because silence was never an answer.

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
- [`docs/design-tokens.md`](docs/design-tokens.md) — the palette, type and the shared UI kit
- [`docs/dev-logins.md`](docs/dev-logins.md) — every development credential, in one place
- [`docs/deployment.md`](docs/deployment.md) — going live, real providers, GDPR
- [`Project_view.md`](Project_view.md) — the version 2.0 specification this implements
