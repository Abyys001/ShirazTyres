import 'dart:convert';

import 'app_storage.dart';

/// JWTs live in the platform keystore, never in shared preferences.
///
/// Sign-in is meant to survive for as long as the app is installed, so every
/// read is defensive: an entry the keystore can no longer decrypt (it came back
/// from an OS backup without the key that wrote it) has to read as "nothing
/// stored" rather than throw, or the splash screen never resolves.
///
/// Every access catches *everything*, not a platform exception alone. On the
/// web this package encrypts through `crypto.subtle`, which a browser only
/// exposes in a secure context — over plain http, on anything but localhost,
/// it is simply absent and the plugin fails a null check rather than raising
/// something typed. That threw straight through a sign-in that had already
/// succeeded: the code was spent, the session was never stored, the screen
/// never moved, and the next attempt was refused as a code nobody asked for.
/// Storage that cannot be reached is a session that does not outlive the tab,
/// which is a thing to live with; it is not a reason to fail signing in.
class TokenStore {
  const TokenStore(this._storage);

  final AppStorage _storage;

  static const _accessKey = 'st_access';
  static const _refreshKey = 'st_refresh';
  static const _profileKey = 'st_profile';

  Future<String?> readAccess() => _read(_accessKey);

  Future<String?> readRefresh() => _read(_refreshKey);

  /// The last profile the API confirmed. Lets a cold start with no signal open
  /// on the account it opened on yesterday instead of on the sign-in screen.
  Future<Map<String, dynamic>?> readProfile() async {
    final raw = await _read(_profileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.map((key, value) => MapEntry('$key', value)) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> saveProfile(Map<String, dynamic> profile) =>
      _write(_profileKey, jsonEncode(profile));

  Future<void> save({required String access, required String refresh}) async {
    await _write(_accessKey, access);
    await _write(_refreshKey, refresh);
  }

  Future<void> clear() async {
    await _delete(_accessKey);
    await _delete(_refreshKey);
    await _delete(_profileKey);
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      await _delete(key);
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Nothing to be done about it here; the session simply will not survive
      // this launch, and the next sign-in writes again.
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Already unreadable, which is all the caller wanted.
    }
  }
}
