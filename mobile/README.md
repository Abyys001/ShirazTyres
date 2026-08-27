# ShirazTyres — driver app

Flutter client for the driver-facing side of the ShirazTyres API: phone/OTP
sign-in, saved vehicles with DVLA + tyre-size lookup, one-tap emergency
call-out with GPS, and live status tracking.

## Layout

```
lib/
  api/        one class per API area (auth, bookings, vehicles, devices)
  core/       config, Dio client + token refresh, secure token store, router, theme
  models/     plain Dart models with hand-written fromJson
  providers/  Riverpod providers and controllers
  screens/    one file per screen
  widgets/    shared presentational widgets
```

State: **Riverpod** (`Notifier` / `AsyncNotifier`). Navigation: **go_router**,
with a single `redirect` that owns the signed-in/signed-out split. HTTP:
**dio**, with an interceptor that attaches the driver JWT and, on a 401,
refreshes once and replays the request.

## First run

The platform folders are not committed — generate them, then install deps:

```bash
cd mobile
flutter create . --project-name shiraztyres --org uk.co.shiraztyres --platforms=android,ios
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

`10.0.2.2` is the host machine as seen from the Android emulator. On a physical
device use your machine's LAN address; in production pass the real host.

Available `--dart-define` keys: `API_BASE_URL`, `SHOP_PHONE`.

While the backend runs with `SMS_PROVIDER=mock`, the OTP request response
carries a `debug_code` and the app pre-fills the code box, so you can sign in
without an SMS gateway.

## Native setup after `flutter create`

**`android/app/src/main/AndroidManifest.xml`** — above `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

and inside `<queries>` (add the element if absent) so `tel:` links resolve:

```xml
<queries>
  <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
  <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
</queries>
```

`flutter_secure_storage` needs `minSdkVersion 23` in
`android/app/build.gradle.kts`.

**`ios/Runner/Info.plist`**:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to send a fitter straight to your vehicle.</string>
<key>LSApplicationQueriesSchemes</key>
<array><string>tel</string></array>
```

## Push notifications

Push is behind `PushService` (`lib/providers/push.dart`) and ships as a no-op so
the app builds with no Firebase project attached. To turn it on:

1. Add `firebase_core` and `firebase_messaging` to `pubspec.yaml`.
2. Drop `google-services.json` / `GoogleService-Info.plist` into the platform
   folders and apply the Google Services Gradle plugin.
3. Implement `FcmPushService.deviceToken()` as
   `FirebaseMessaging.instance.getToken()` and override `pushServiceProvider`.

The app already registers and de-registers the token against `POST /devices` and
`DELETE /devices` at sign-in and sign-out, so no other change is needed.
