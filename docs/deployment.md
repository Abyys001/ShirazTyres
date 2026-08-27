# Deployment

## Shape

```
                    ┌─────────────┐
  website widget ──►│             │
  panel (Next.js) ──►   Django    ├──► PostgreSQL 16
  Flutter app  ────►│   + DRF     ├──► Redis ──► Celery worker + beat
                    └──────┬──────┘
                           ├──► DVLA VES        (vehicle data)
                           ├──► tyre fitment API (tyre size)
                           ├──► Twilio          (SMS)
                           └──► FCM             (push)
```

Run the API under gunicorn behind nginx; run `celery worker` and `celery beat`
as separate processes. The panel runs as its own Node process (`next start`)
or on any Next.js host. Nothing in the API is stateful beyond Postgres and
Redis.

## Environment

Start from `.env.example`. The settings that must change before going live:

| Variable | Why |
|---|---|
| `DJANGO_SECRET_KEY` | anything but the default |
| `DJANGO_DEBUG=0` | required |
| `DJANGO_ALLOWED_HOSTS` | the real hostnames |
| `CORS_ALLOWED_ORIGINS` / `CSRF_TRUSTED_ORIGINS` | the website and panel origins |
| `PANEL_BASE_URL` | used in the notification deep links |
| `SMS_PROVIDER=twilio` + credentials | real OTPs and shop alerts |
| `PUSH_PROVIDER=fcm` + credentials | real push |
| `VEHICLE_LOOKUP_MOCK=0` + `DVLA_API_KEY` + `TYRE_API_KEY` | real lookups |
| `SHOP_NOTIFY_SMS` / `SHOP_NOTIFY_EMAIL` | where call-outs land |
| `EMAIL_HOST` and friends | outbound email |

## Third-party lead times

Two of these cannot be rushed and should be started before the build is
finished:

- **DVLA Vehicle Enquiry Service** — an application, not a signup. Expect
  weeks, and expect to justify the use case.
- **Commercial tyre fitment API** — a paid contract, per-lookup pricing.

Both are behind provider classes with mock implementations
(`apps/vehicles/providers.py`), so the rest of the system is finished, tested
and demonstrable while the paperwork is in flight. Flipping
`VEHICLE_LOOKUP_MOCK=0` is the whole switchover.

## Cost control

Lookups are cached per plate on a `VEHICLE_LOOKUP_TTL_DAYS` TTL and the public
lookup endpoint is throttled to 30/hour. Anonymous callers cannot pass
`?refresh=1`, so nobody can burn the DVLA quota from the website.

## Data protection

The system holds names, phone numbers, email addresses and — while a call-out
is live — precise locations. That is personal data under UK GDPR.

- Location is collected for one purpose (getting a fitter to a vehicle) and is
  worth a retention rule: drop lat/long from completed bookings after the
  period the shop agrees to.
- `purge_expired_otps` and `purge_old_notifications` already run on Celery
  beat; add a booking-retention task alongside them when the retention period
  is decided.
- The privacy notice on the website needs a line covering the widget's
  location prompt and the DVLA lookup, before it goes live.
- Notification rows record recipients and delivery status; treat that log as
  personal data too.

These are decisions for the client, not defaults to guess at — the hooks are in
place either way.

## Backups

Postgres is the only durable store. `pg_dump` on a schedule plus WAL archiving
covers it; Redis holds cache and the Celery queue and can be lost.

## Health

`/api/schema/` and `/api/docs/` confirm the app is serving. The compose file
health-checks Postgres and Redis. Add an uptime check against
`GET /api/v1/vehicle-lookup/AB12CDE` with `VEHICLE_LOOKUP_MOCK=1` on a staging
host if you want a synthetic end-to-end probe.
