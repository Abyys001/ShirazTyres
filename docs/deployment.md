# Deployment

## Shape

```
  marketing-site widget ─┐
  customer website ──────┤
  customer app ──────────┤    ┌──────────────┐
  owner panel ───────────┼───►│  Django 5    ├──► PostgreSQL 16
  technician app ────────┘    │  DRF + ASGI  ├──► Redis ──► Celery worker + beat
                              └──────┬───────┘         └──► Channels layer (WebSocket)
                                     ├──► DVLA VES            (vehicle data)
                                     ├──► tyre fitment API    (tyre size)
                                     ├──► routing engine      (travel time and ETA)
                                     ├──► OSM tile provider   (maps)
                                     ├──► Twilio              (SMS)
                                     └──► FCM                 (push)
```

Run the API under **daphne** — not gunicorn — behind nginx: the panel's live map,
the customer's ETA feed and the technician's offer stream are all WebSocket, and
WSGI cannot carry them. `celery worker` and `celery beat` run as separate
processes; beat is not optional, because dispatch timeouts, document-expiry
warnings and location retention all run from it.

Both Next.js apps run as their own Node processes (`next start`) or on any
Next.js host. Nothing in the API is stateful beyond Postgres and Redis.

nginx must serve `MEDIA_ROOT` (driver photographs and documents) and proxy
`/ws/` with the upgrade headers.

## Environment

Start from `.env.example`. The settings that must change before going live:

| Variable | Why |
|---|---|
| `DJANGO_SECRET_KEY` | anything but the default |
| `DJANGO_DEBUG=0` | required |
| `DJANGO_ALLOWED_HOSTS` | the real hostnames |
| `CORS_ALLOWED_ORIGINS` / `CSRF_TRUSTED_ORIGINS` | the website and panel origins |
| `PANEL_BASE_URL` / `CUSTOMER_BASE_URL` | used in notification deep links |
| `CHANNEL_LAYER_URL` | Redis for WebSocket fan-out; without it realtime is single-process |
| `SMS_PROVIDER=twilio` + credentials | real OTPs and owner alerts |
| `PUSH_PROVIDER=fcm` + credentials | real push |
| `VEHICLE_LOOKUP_MOCK=0` + `DVLA_API_KEY` + `TYRE_API_KEY` | real lookups |
| `GOOGLE_OAUTH_MOCK=0` + `GOOGLE_OAUTH_CLIENT_IDS` | real Google sign-in |
| `ROUTING_PROVIDER` + `ROUTING_BASE_URL` | **see below — the mock must not reach production** |
| `MAP_TILE_URL` | a commercial OSM provider, never OSM's own tile server |
| `SHOP_NOTIFY_SMS` / `SHOP_NOTIFY_EMAIL` | where call-outs land |
| `EMAIL_HOST` and friends | outbound email |

`GOOGLE_OAUTH_CLIENT_IDS` takes **every** client id that may sign a token you
accept: the web client, the Android client and the iOS client.

### Routing is not optional

`ROUTING_PROVIDER=mock` computes travel time as straight-line distance at 24 kph.
It exists for development and CI. In production it would rank candidates by
crow-flight, which is exactly what specification 6.4 says must never happen, and
it would quote customers an ETA that is wrong in a way they can see. Point
`ROUTING_BASE_URL` at a self-hosted OSRM or Valhalla, or use GraphHopper.

Then calibrate `TRAFFIC_FACTOR_*` against real journey times. A default OSRM
profile is optimistic in central London, and an ETA that is consistently fifteen
minutes wrong is worse than showing no ETA at all.

### Map tiles

Do not point production at OSM's own tile server. The OpenStreetMap Foundation's
usage policy warns commercial services that access may be withdrawn at any point,
which for a dispatch platform is an outage of the core product. Use MapTiler,
Stadia, Geoapify or Thunderforest, or self-host OpenMapTiles. OSM attribution
must stay visible on every map and must not be hidden behind a toggle.

## Third-party lead times

Start these in phase 0; several have real waiting time.

| Item | Lead time |
|---|---|
| DVLA VES API approval | 1–14 days, one key per company |
| Tyre fitment data contract | varies by provider |
| Apple Developer Program account | days, plus a Mac to build on |
| Apple Unlisted App request for the technician app | 5–7 business days, requested separately from review |
| Google Play background-location declaration | submitted with the first release |

## Mobile releases

**Technician app (`mobile/`).** Apple Guideline 3.2 does not allow an app that is
only usable by a company's own staff to sit on the public App Store. Use Unlisted
App Distribution (a public link that does not appear in search) or Apple Business
Manager. Decide which before phase 7, because the request is separate from review
and takes its own week.

Android background location (`ACCESS_BACKGROUND_LOCATION`) needs a written
justification submitted to Google Play, and iOS "Always" location needs one at
App Review. Both are approvable for a genuine dispatch application. The
justification to give is the true one: the technician's position is used only
while they are toggled online, to route the nearest job to them and to give the
customer an accurate arrival time.

**Customer app (`mobile_customer/`).** Ordinary store distribution, foreground
location only.

Both apps take their API host at build time:

```bash
flutter build appbundle \
  --dart-define=API_BASE_URL=https://api.shiraztyres.co.uk/api/v1 \
  --dart-define=WS_BASE_URL=wss://api.shiraztyres.co.uk/ws
```

## Data protection

Continuous location tracking of employees, storage of insurance and licence
documents, and customer account data are all regulated processing under UK GDPR.
The build-side commitments are implemented as follows, and should be checked
against whatever the business's own compliance review concludes:

- **Tracking is limited to online hours.** `record_location` refuses a fix from
  an offline driver, and going offline clears the last known position.
- **Location history has a defined retention period.**
  `drivers.location_retention_days` (90 by default) is enforced nightly by
  `purge_driver_locations`.
- **Driver documents are access-controlled.** They are staff-only; no customer
  surface can reach them, and the driver's own serializer hides the staff
  reference field.
- **Customer data is held only as long as the account exists.** Deleting a
  customer cascades.

The customer never receives a technician's position, personal phone number,
insurance number or document scan. That boundary is enforced in the serializers
and in `apps/realtime/publish.py`, and is covered by tests — treat those tests as
part of the compliance story, not merely as regression cover.

## Backups

Postgres is the only durable store; Redis holds queues and cache. Take
`pg_dump` nightly and keep the media directory (driver photographs and
documents) in the same backup schedule.

## Health

- `GET /api/v1/public/config` is a cheap end-to-end check: it touches settings,
  the cache and the database.
- `celery -A config inspect ping` for the worker.
- Watch the log line `dispatch.swept_expired` — if it appears regularly, the
  worker is losing countdown tasks and the beat sweep is doing work it should
  not have to.
