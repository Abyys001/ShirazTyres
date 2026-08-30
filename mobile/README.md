# ShirazTyres — technician app

Flutter client for ShirazTyres field technicians. Restricted distribution: this
app is for employees, not the public.

Terminology follows specification section 2 — in this codebase a **driver** is
always the technician, never the customer.

## What it does

- Phone/OTP sign-in, then onboarding: name, photograph, van registration, and
  the insurance, licence and MOT documents an administrator has to approve (8.1).
- An online/offline toggle. Going online is the **only** thing that starts
  location reporting, and going offline stops it and clears the last known
  position (11.1).
- Live offers over a WebSocket, with a countdown. Accept or reject — rejection is
  a first-class answer in both dispatch modes and sends the job straight to the
  next technician (6.3).
- The job flow: on the way, arrived, working, complete, with one-tap navigation
  and a call button.
- On-site invoicing: the call-out fee is already there, parts and labour come
  from the owner's price list or free text, VAT is applied, and one payment is
  taken at the end (7.1).
- Correcting the tyre size when the car does not match what was recorded (9.3).

## Layout

```
lib/
  api/        one class per API area (auth, driver, jobs, devices)
  core/       config, Dio client + token refresh, secure token store,
              offer socket, location, router, theme
  models/     plain Dart models with hand-written fromJson
  providers/  Riverpod providers and controllers
  screens/    one file per screen
  widgets/    shared presentational widgets
```

State: **Riverpod** (`Notifier` / `AsyncNotifier`). Navigation: **go_router**,
with a single `redirect` that owns the signed-out / onboarding / working split.
HTTP: **dio**, with an interceptor that attaches the driver JWT and, on a 401,
refreshes once and replays the request.

## Run it

```bash
cd mobile
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8000/ws
```

`10.0.2.2` is the host machine as seen from the Android emulator. On a physical
device use your machine's LAN address; in production pass the real host.

`--dart-define` keys: `API_BASE_URL`, `WS_BASE_URL`, `OFFICE_PHONE`.

While the backend runs with `SMS_PROVIDER=mock`, the OTP request response carries
a `debug_code` and the app pre-fills the code box, so you can sign in with no SMS
gateway. `make seed` leaves four approved technicians and one pending one.

## Location and battery

Updates go on a **distance filter** (75 m by default), not a timer, with a
two-minute heartbeat so a stationary van still checks in. Fixes that cannot be
sent are buffered and flushed when signal returns — a technician on a hard
shoulder is exactly where the signal goes. Continuous streaming would flatten the
phone before the end of a shift.

## Native permissions

`AndroidManifest.xml` and `Info.plist` already carry what the app needs,
including `ACCESS_BACKGROUND_LOCATION` and the iOS "Always" strings. Both stores
require a written justification for these; see `docs/deployment.md` before the
first release.

`flutter_secure_storage` needs `minSdkVersion 23`.

## Push notifications

Push is behind `PushService` (`lib/providers/push.dart`) and ships as a no-op so
the app builds with no Firebase project attached. To turn it on:

1. Add `firebase_core` and `firebase_messaging` to `pubspec.yaml`.
2. Drop `google-services.json` / `GoogleService-Info.plist` into the platform
   folders and apply the Google Services Gradle plugin.
3. Implement `FcmPushService.deviceToken()` as
   `FirebaseMessaging.instance.getToken()` and override `pushServiceProvider`.

The app already registers and de-registers the token at sign-in and sign-out.
Push wakes the phone for a new offer; the WebSocket keeps an open app current.

## Distribution

Apple Guideline 3.2 does not allow an employees-only app on the public App Store.
Use Unlisted App Distribution or Apple Business Manager — the decision is
specification section 16 item 3, and the request has its own lead time.
