# Data model

## Entities

**StaffUser** (`accounts`) — the Django auth user. Email login, role `owner`
or `staff`.

**Driver** (`accounts`) — deliberately *not* a Django user. A driver is a
verified phone number (E.164, unique) plus an optional name and email. No
password exists to be stolen or reset.

**OtpCode** (`accounts`) — hashed code, purpose (`login` / `booking`),
expiry, attempt counter, used-at. Retired when a newer code is issued for the
same phone and purpose. Expired rows are purged by a Celery beat task.

**Vehicle** (`vehicles`) — one row per plate, shared by every driver and
booking that references it. Holds DVLA fields (make, model, colour, fuel, MOT,
tax) and tyre fields (front/rear size, load index, speed rating, pressures,
size options) with a separate `dvla_fetched_at` / `tyre_fetched_at` so each
source ages on its own TTL. `tyre_source` records where the size came from —
`api`, `staff` or `driver`; the last two are never overwritten by a later
automated lookup.

**DriverVehicle** (`vehicles`) — a driver's saved vehicles, with nickname and
a primary flag so the app can pre-fill a call-out.

**Booking** (`bookings`) — the call-out. Reference `ST-XXXXXX`. Contact name,
phone and email are denormalised onto the row rather than read through the
driver, so a phone-in taken by the shop needs no Driver record at all.
Location is free text and/or lat/long; `maps_url()` builds the link the fitter
taps.

**BookingStatusEvent** (`bookings`) — one row per transition: from, to, note,
who, when. This is the audit trail the panel timeline and the app tracker both
render.

**DeviceToken** / **Notification** (`notifications`) — push targets (owned by
a driver *or* a staff user) and the delivery log for every push, SMS and email
the system sends.

## Status machine

```
received ──► assigned ──► in_progress ──► completed
   │            │              │
   └────────────┴──────────────┴──► cancelled
```

`assigned` may also go back to `received` (a fitter falls through).
`completed` and `cancelled` are terminal. The legal moves live in
`Booking.ALLOWED_TRANSITIONS` and are enforced in `transition_booking()`, not
in the view — so the rule holds for the panel, the admin and any future
surface alike.

Side effects hang off the transition, after the transaction commits:

- entering the system → push to every active staff device, SMS to
  `SHOP_NOTIFY_SMS`, email to `SHOP_NOTIFY_EMAIL` with the maps link and a
  deep link into the panel
- any status change → push to the driver's devices

Because they are queued with `transaction.on_commit`, a rolled-back booking
never produces a notification.

## Lookup freshness

`lookup_plate(plate, force_refresh=False)`:

1. Load or create the `Vehicle` row for the normalised plate.
2. If `dvla_fetched_at` is older than `VEHICLE_LOOKUP_TTL_DAYS` (or missing),
   call DVLA. A not-found on a brand-new row deletes the shell and raises.
3. If `tyre_fetched_at` is stale and the size was not human-confirmed, call the
   tyre API. A failure here records `lookup_error` and returns the vehicle
   anyway.

So the worst case is a vehicle with a plate and no tyre size — which the panel
and the app both render as "confirm the size with the driver", rather than an
error page in front of someone stranded on a hard shoulder.
