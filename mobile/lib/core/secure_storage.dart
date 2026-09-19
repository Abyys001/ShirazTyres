import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_storage.dart';

/// The one secure store this app uses, for tokens, the cached profile and
/// preferences alike.
///
/// **The web namespace is not decoration.** On Android and iOS each app has its
/// own sandbox, so both apps can and do use the same key names. The web builds
/// are served from a single origin — the panel's — where the secure storage
/// falls back to `localStorage` and every key is prefixed with `publicKey`.
/// Left at its default the two apps share one namespace, and whichever signed
/// in last hands its token to the other: the technician app opened with a driver's
/// token and every call came back 403.
const FlutterSecureStorage appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  webOptions: WebOptions(
    dbName: 'shiraztyres_driver',
    publicKey: 'shiraztyres_driver',
  ),
);

/// What the stores actually take: the encrypted store above, and the fallback
/// for the one case where a browser will not provide it.
const AppStorage appStorage = AppStorage(appSecureStorage);
