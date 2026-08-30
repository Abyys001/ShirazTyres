# Data model

Postgres 16 in production, SQLite for the test suite. Everything below lives in
`backend/apps/`.

## Entities

| Model | App | Holds |
|---|---|---|
| `StaffUser` | accounts | The owner and office staff. The only Django users. |
| `Customer` | accounts | The motorist. Phone, email, Google link, verification flags. |
| `SocialIdentity` | accounts | One Google account linked to one customer. |
| `OtpCode` | accounts | Hashed, single-use, expiring codes, scoped by purpose. |
| `Vehicle` | vehicles | A customer's car by plate: DVLA data plus tyre specification. |
| `CustomerVehicle` | vehicles | The link between a customer and a car, and the confirmation record. |
| `Driver` | drivers | The technician: profile, verification, availability, last position. |
| `DriverVehicle` | drivers | The service van. |
| `DriverDocument` | drivers | Insurance, licence, MOT — file, expiry, review state. |
| `DriverLocation` | drivers | The position time series, with a retention policy. |
| `ServiceArea` | geo | A GeoJSON boundary, a priority, and per-area dispatch overrides. |
| `Job` | bookings | The call-out. |
| `JobStatusEvent` | bookings | Every status change, and who made it. |
| `DispatchAttempt` | dispatch | One round: mode, radius, timeout, outcome. |
| `DispatchOffer` | dispatch | One offer to one driver within a round. |
| `ServiceItem` | billing | The owner's price list. |
| `Invoice` | billing | One per job, with the VAT rate snapshotted. |
| `InvoiceLineItem` | billing | The call-out fee, parts, labour. |
| `Setting` | configuration | Overrides only — defaults live in the catalogue. |
| `Notification` | notifications | What was sent, to whom, and whether it landed. |
| `DeviceToken` | notifications | Push tokens for customers, drivers and staff. |

### Two vehicle tables, on purpose

`vehicles.Vehicle` is the customer's broken-down car. `drivers.DriverVehicle` is
the technician's van. They are deliberately separate, with their own make, model
and colour: they have different owners, different lifecycles, and different
audiences, and merging them would put a van into the customer-facing tyre cache.
A van's plate lookup calls DVLA directly without creating a `Vehicle` row.

### `CustomerVehicle` carries more weight than its size suggests

It stores both the looked-up and the customer-supplied tyre specification, plus
which confirmation path was taken and when the responsibility notice was
accepted. When a technician arrives with a tyre that does not fit, this record
settles what was shown, what was entered, and who accepted responsibility.

### `DispatchAttempt` makes dispatch auditable

When a job goes unclaimed it shows exactly which drivers were contacted, when,
and whether each rejected or simply never responded.

## The job status machine

Ten statuses:

```
submitted → dispatching → assigned → accepted → en_route → arrived → in_progress → completed
                ↓             ↓          ↓          ↓
            unclaimed     dispatching (rejection or timeout: back to the pool)

cancelled is reachable from everything except completed.
```

`Job.ALLOWED_TRANSITIONS` is the authority; `transition_job()` refuses anything
else, stamps the matching timestamp, writes a `JobStatusEvent`, notifies, and
publishes to the realtime channels. The panel mirrors the table so it does not
offer a move the API will refuse, but never decides on its own.

`unclaimed` is the one that needs a person: nobody took the job, so the owner is
alerted and the queue shows it in red.

Statuses the customer sees are a subset: `assigned` is internal, because until a
technician has actually accepted, the honest thing to tell a customer is that we
are still looking.

## Dispatch

One round is a `DispatchAttempt` with one `DispatchOffer` per driver contacted.

1. A haversine pre-filter narrows the pool to the current radius. This is a
   cost control on the routing call and nothing else.
2. The routing engine returns travel times for the shortlist in **one matrix
   request**, and that ordering is the ranking. Straight-line distance never
   decides who gets a job (6.4).
3. In automatic mode the best-ranked driver is assigned up front; in selection
   mode the nearest *N* are offered it at once and the first to accept wins.
4. A rejection escalates immediately. A timeout escalates when the deadline
   passes. A driver who has already had the job — rejected or timed out — is
   never offered it again.
5. After `dispatch.max_attempts` rounds the configured fallback applies: retry,
   switch mode, or mark `unclaimed`.

Timeouts are Celery countdown tasks, with a beat sweep every 30 seconds as a
safety net for a countdown lost to a worker restart.

## Service areas without PostGIS

The specification calls for PostGIS. This build stores boundaries as GeoJSON and
does point-in-polygon in plain Python, isolated in `apps/geo/geometry.py`.

The trade-off is deliberate: a handful of London-sized polygons make ray casting
free, and it keeps the `USE_SQLITE` development and CI path working without GDAL
and GEOS. Driver *ranking* never uses these distances — that is the routing
engine's job — so this is only ever a coarse pre-filter and a containment test.
If the polygon count ever makes it hot, swap that one module for PostGIS;
nothing outside it knows how containment is decided.

## Settings

`apps/configuration/catalogue.py` declares every knob in specification section
12 with its type, default, label and help text. The `Setting` table stores
**overrides only**, so a fresh install is fully configured and a default can be
changed in code without a data migration.

All overrides are cached under one key, because dispatch reads six or seven of
them per job and one cache round-trip beats seven. A `ServiceArea` may override
any `dispatch.*` key for jobs inside it; nothing else is overridable per area.

## Money

Decimal throughout, `ROUND_HALF_UP`. The VAT rate is snapshotted onto the
invoice when the job is created, so changing the rate never rewrites yesterday's
invoices. The call-out fee is added as a system line that the technician cannot
remove on site.
