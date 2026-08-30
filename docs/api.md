# API reference

Base path `/api/v1`. Everything is JSON. The live, generated reference is at
`/api/docs/` (Swagger UI, from `backend/openapi.yaml`); this page is the
narrative version.

Terminology follows specification section 2: a **customer** is the motorist, a
**driver** is a ShirazTyres technician.

## Error shape

Every error is flattened to one shape by `config/exceptions.py`:

```json
{ "detail": "Validation failed.", "errors": { "contact_phone": ["Enter a UK mobile number."] } }
```

Clients read `detail` for the banner and `errors[field]` for the input.

## Authentication

Three audiences share one token format, separated by a `scope` claim. A token
issued for one scope is rejected by every endpoint belonging to another, and the
WebSocket handshake checks the same claim.

### Customers — Google or phone OTP, one account either way

```http
POST /auth/otp/request           { "phone": "07700900123", "purpose": "login" }
  -> { "expires_at": "...", "resend_after_seconds": 60, "debug_code": "123456" }

POST /auth/customer/otp/verify   { "phone": "07700900123", "code": "123456" }
  -> { "access": "...", "refresh": "...", "is_new_customer": true, "customer": {...} }

POST /auth/customer/google       { "id_token": "<Google ID token>" }
  -> { "access": "...", "refresh": "...", "is_new_customer": false, "customer": {...} }

POST /auth/customer/attach-phone { "phone": "07700900123", "code": "123456" }
POST /auth/customer/refresh      { "refresh": "..." }
GET  /customers/me
```

The Google ID token is verified against Google's keys server-side; a `sub` or
`email` the client merely claims is never trusted. A Google account whose
**verified** email matches an existing customer resolves to that customer, which
is what makes both sign-in routes reach one job history.

### Drivers — phone OTP, then approval

```http
POST /auth/otp/request        { "phone": "07700900201", "purpose": "driver" }
POST /auth/driver/otp/verify  { "phone": "07700900201", "code": "123456", "name": "Amir" }
POST /auth/driver/refresh     { "refresh": "..." }
```

A code issued with `purpose: "login"` cannot be spent on the driver endpoint, or
the other way round.

### Staff — email and password

```http
POST /auth/staff/login    { "email": "owner@shiraztyres.co.uk", "password": "..." }
POST /auth/staff/refresh  { "refresh": "..." }
GET  /auth/staff/me
```

`debug_code` appears only while `SMS_PROVIDER=mock`. Codes are hashed with
Django's password hasher, single-use, `OTP_TTL_SECONDS`-bound, capped at
`OTP_MAX_ATTEMPTS`, and throttled at 5 requests/hour and 10 verifications/hour.

## Public — no token at all

```http
GET  /public/config                    fee, VAT, issue types, hours, out-of-area text
POST /public/coverage                  { "latitude": "51.5074", "longitude": "-0.1278" }
                                         -> { "covered": true, "area": "London", "message": "" }
GET  /public/vehicle-lookup/{plate}     DVLA data + manufacturer tyre specification
```

These three are what the marketing-site widget uses, and nothing else is
anonymous.

## Customer surfaces

```http
GET  /my/jobs                  the customer's own jobs, newest first
GET  /my/jobs/active           the job in progress, or { "job": null }
POST /my/jobs                  submit a request
GET  /my/jobs/{id}             detail, with a timeline
POST /my/jobs/{id}/cancel      up to the configured point in the lifecycle
GET  /my-vehicles              the customer's saved vehicles
POST /my-vehicles/{id}/confirm-tyre
```

Submission payload:

```json
{
  "plate": "AA19AAA",
  "issue_type": "puncture",
  "description": "Nearside front, flat.",
  "latitude": "51.5074",
  "longitude": "-0.1278",
  "location_accuracy_m": 12,
  "location_source": "device",
  "location_text": "Hard shoulder past the Perivale exit",
  "tyre_confirmation": {
    "confirmation_path": "confirmed",
    "tyre_size": "205/55R16",
    "disclaimer_accepted": false
  }
}
```

- A position is **required**. There is no postcode field, by design (4.4).
- `confirmation_path` is `confirmed` (path A) or `overridden` (path B). Path B
  is refused unless `disclaimer_accepted` is true and a size is given, and the
  job then stores both the looked-up and the customer-supplied values (4.3).
- Out of area returns 400 with the configured message; out of hours returns 400
  with `errors.out_of_hours` when the owner has set the refuse behaviour.

What comes back about the assigned technician is exactly six fields —
`first_name`, `photo`, `vehicle_make`, `vehicle_model`, `vehicle_colour`,
`vehicle_plate` — plus `eta_minutes`. No coordinates, ever (4.6, 4.7).

## Driver app

```http
GET   /driver/me                       PATCH for name, email, photo
POST  /driver/online                   { "is_online": true }
POST  /driver/location                 one fix, or { "points": [...] } after a signal drop
GET   /driver/offers                   live offers, with the job attached
GET   /driver/jobs                     own jobs;  GET /driver/jobs/{id}
POST  /driver/jobs/{id}/accept
POST  /driver/jobs/{id}/reject         { "reason": "Already loaded" }
POST  /driver/jobs/{id}/status         { "status": "en_route" }
POST  /driver/jobs/{id}/correct-tyre   { "tyre_size": "215/50R17" }
GET   /driver/jobs/{id}/invoice
POST  /driver/jobs/{id}/invoice/lines  { "service_item_id": 3 } or a free-text line
DELETE /driver/jobs/{id}/invoice/lines/{line_id}
POST  /driver/jobs/{id}/complete       { "payment_method": "card_reader" }
GET   /driver/service-items            the price list
POST  /driver/vehicles                 the van; make/model/colour fill in from the plate
POST  /driver/documents                multipart: type, file, expiry_date
```

Rejecting is allowed in **both** dispatch modes and escalates immediately (6.3).
Location is refused while the driver is offline (11.1). Completing takes the
single payment and closes the job (7.1).

## Owner panel

```http
GET   /jobs                     filters: status, open_only, needs_attention, issue_type,
                                source, driver, assigned_staff, service_area, created_after/before
GET   /jobs/stats               queue counts, plus drivers online
POST  /jobs                     manual entry — the phone-in path
GET   /jobs/{id}                detail, with status history, invoice and the dispatch trail
PATCH /jobs/{id}                office edits
POST  /jobs/{id}/status         { "status": "cancelled", "note": "Duplicate" }
POST  /jobs/{id}/assign         { "driver_id": 4 } — by hand, out of the unclaimed queue
POST  /jobs/{id}/dispatch       run dispatch again from round one
GET   /jobs/{id}/candidates     who would be offered this, without offering it
GET   /jobs/{id}/invoice        POST to add a line the technician could not

GET   /drivers                  filters: verification_status, is_active, is_online, service_areas
GET   /drivers/{id}             POST /drivers/{id}/verification to approve, suspend or reject
GET   /drivers/{id}/documents   POST /driver-documents/{id}/review
GET   /drivers/{id}/location-history
GET   /drivers/map              live positions — staff only
GET   /drivers/compliance       onboarding queue and the expiry watchlist

GET   /service-areas            owner-only for writes; boundaries are GeoJSON
GET   /settings                 values plus the specs needed to render them; PATCH is owner-only
GET   /service-items            the price list; owner-only for writes
GET   /invoices                 POST /invoices/{id}/mark-paid, /void

GET   /vehicles/{plate}         the standalone lookup tool — answers for any plate,
                                not only ones already on a job; ?refresh=1 bypasses the cache
POST  /vehicles/{plate}/refresh
POST  /vehicles/{plate}/confirm-tyre

GET   /customers                POST /customers/{id}/send-login-code
GET   /notifications            what has been sent, and whether it landed
POST  /devices                  register a push token; DELETE to deregister
```

## WebSocket

Three channels, one per audience, at `ws/…` on the same host. The token goes in
the query string because a browser cannot set a header on a handshake; it is the
same scoped access token, verified the same way.

| Channel | Who | Carries |
|---|---|---|
| `ws/panel?token=…` | staff | every job event, and live driver positions |
| `ws/customer?token=…` | customers | their own jobs: status and the ETA figure |
| `ws/driver?token=…` | drivers | offers, withdrawals, and their job's status |

The customer channel never carries a coordinate. That boundary lives in
`apps/realtime/publish.py` and is covered by tests.

## Throttling

| Scope | Default |
|---|---|
| `otp_request` | 5/hour |
| `otp_verify` | 10/hour |
| `vehicle_lookup` | 30/hour |
| `job_create` | 10/hour |

All are `THROTTLE_*` environment variables.
