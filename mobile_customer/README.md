# ShirazTyres — customer app

Flutter client for customers: request a technician, and follow the job.

The same functionality as `website/`, through a different client. All the logic
lives in the backend and both clients are thin presentation layers — that is what
keeps the second implementation cheap rather than doubling the cost.

## What it does

- Sign in with Google or phone OTP. Both routes reach the same account and the
  same job history (4.1). A Google-first customer can attach a phone number from
  the account screen.
- Registration lookup: the vehicle and the manufacturer's tyre size (4.2).
- **Tyre confirmation, which the request cannot skip** (4.3). Confirm the
  looked-up size, or decline — in which case a responsibility notice appears, has
  to be acknowledged, and only then do the fields open. Both figures are sent.
- Native location permission, which is what gives the accuracy needed at the
  roadside. There is no postcode field by design, and a position outside the
  service area is refused with the configured message (4.4).
- Tracking: status, the technician's first name, photograph and van, and a live
  ETA that updates over a WebSocket (4.6).

**No map, and no technician position.** The ETA is recalculated on the backend
each time the van moves and only the figure is sent. That is deliberate: it keeps
an employee's live position off customer surfaces, and stops a customer watching
a stationary pin at a junction and drawing conclusions from it.

## Layout

```
lib/
  api/        auth, jobs, devices
  core/       config, Dio client + token refresh, secure token store,
              job socket, location, router, theme
  models/     plain Dart models with hand-written fromJson
  providers/  Riverpod providers and controllers
  screens/    sign-in, home, request, job, history, account
  widgets/    shared presentational widgets
```

## Run it

```bash
cd mobile_customer
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8000/ws
```

`--dart-define` keys: `API_BASE_URL`, `WS_BASE_URL`, `OFFICE_PHONE`,
`GOOGLE_SERVER_CLIENT_ID`.

With `SMS_PROVIDER=mock` the OTP response carries a `debug_code` and the app
pre-fills it. Google sign-in needs `GOOGLE_SERVER_CLIENT_ID` and the matching
client id in the backend's `GOOGLE_OAUTH_CLIENT_IDS`; without it the button
reports that Google sign-in is not configured in this build, and phone OTP still
works.

## Push notifications

Behind `PushService` and shipping as a no-op, exactly as in the technician app —
see `mobile/README.md` for the three steps to turn it on.
