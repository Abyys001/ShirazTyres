# API reference

Base path `/api/v1`. Everything is JSON. The live, generated reference is at
`/api/docs/` (Swagger UI, from `backend/openapi.yaml`); this page is the
narrative version.

## Error shape

Every error is flattened to one shape by `config/exceptions.py`:

```json
{ "detail": "Validation failed.", "errors": { "contact_phone": ["Enter a UK mobile number."] } }
```

Clients read `detail` for the banner and `errors[field]` for the input.

## Authentication

Two audiences share one token format, separated by a `scope` claim.

### Drivers — phone + OTP

```http
POST /auth/otp/request      { "phone": "07700900123", "purpose": "login" }
  -> { "expires_at": "...", "resend_after_seconds": 60, "debug_code": "123456" }

POST /auth/otp/verify       { "phone": "07700900123", "code": "123456", "name": "Sam" }
  -> { "access": "...", "refresh": "...", "is_new_driver": true, "driver": {...} }

POST /auth/driver/refresh   { "refresh": "..." }  -> { "access": "...", "refresh": "..." }
```

`debug_code` appears only while `SMS_PROVIDER=mock`. `purpose` is `login` for
the app and `booking` for the website widget — a code issued for one cannot be
spent on the other.

Codes are hashed with Django's password hasher, single-use,
`OTP_TTL_SECONDS`-bound, capped at `OTP_MAX_ATTEMPTS`, and throttled at
5 requests/hour and 10 verifications/hour per client.

### Staff — email + password

```http
POST /auth/staff/login      { "email": "...", "password": "..." }
  -> { "access": "...", "refresh": "...", "user": {...} }

POST /auth/staff/refresh    { "refresh": "..." }
GET  /auth/staff/me
```

Send the access token as `Authorization: Bearer <token>`. A token minted for
one audience is silently ignored by the other's authenticator, so it fails as
a plain 401 rather than leaking that the token was otherwise valid.

## Public — no account needed

```http
GET  /vehicle-lookup/{plate}     ?refresh=1 (authenticated callers only)
POST /public/bookings            booking payload + "code" from an OTP with purpose=booking
```

These are what the website widget uses. `POST /public/bookings` is throttled to
10/hour and refuses to create anything without a valid OTP for the phone number
in the payload.

## Driver (scope `driver`)

```http
GET    /drivers/me
PATCH  /drivers/me                { "name": "...", "email": "..." }

GET    /my/bookings               paginated, only this driver's call-outs
GET    /my/bookings/{id}          adds the status timeline
POST   /my/bookings/create        booking payload, no OTP (already signed in)

GET    /my-vehicles
POST   /my-vehicles               { "plate": "...", "nickname": "...", "is_primary": true }
DELETE /my-vehicles/{id}
POST   /my-vehicles/{id}/confirm-tyre   { "tyre_size": "205/55 R16" }

POST   /devices                   { "token": "...", "platform": "android|ios|web" }
DELETE /devices                   { "token": "..." }
```

Driver responses use a reduced serializer: internal notes and staff assignment
never leave the panel.

## Staff (scope `staff`)

```http
GET   /bookings                   filters: status, source, issue_type, assigned_to, date range, search
POST  /bookings                   manual entry, e.g. a phone-in
GET   /bookings/{id}
PATCH /bookings/{id}              contact details, notes, tyre size
PATCH /bookings/{id}/status       { "status": "assigned", "note": "...", "assigned_to_id": 3 }
GET   /bookings/stats             counts for the dashboard header

GET   /drivers                    GET/POST/PATCH
GET   /vehicles                   lookup_field is the plate
POST  /vehicles/{plate}/confirm-tyre
POST  /vehicles/{plate}/refresh   force a fresh DVLA + tyre lookup

GET   /notifications              delivery log
```

## Booking payload

Shared by all three creation endpoints:

```json
{
  "plate": "AB12CDE",
  "contact_name": "Sam Ali",
  "contact_phone": "07700900123",
  "contact_email": "",
  "issue_type": "puncture",
  "description": "Front nearside, spare is flat.",
  "tyre_size": "205/55 R16",
  "location_text": "M6 northbound, past J4",
  "latitude": 52.4862,
  "longitude": -1.8904
}
```

`issue_type` is one of `puncture`, `blowout`, `tyre_damage`, `wheel_change`,
`other`. Either `location_text` or a lat/long pair is required. A plate that
fails lookup is still stored — an emergency call-out is never blocked by an
upstream API being down.
