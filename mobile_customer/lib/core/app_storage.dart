import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'plain_store.dart' if (dart.library.js_interop) 'plain_store_web.dart';

/// The secure store, with a way through when the browser refuses to provide one.
///
/// `flutter_secure_storage` encrypts through `crypto.subtle` on the web, and a
/// browser only exposes that in a secure context. These builds are opened from
/// the panel over plain http on an address that is not localhost, so there is
/// no `subtle` — the plugin fails a null check on every read and write.
///
/// Signing in then succeeded at the API and failed here: the code was spent,
/// the token was never stored, and the very next request went out without it,
/// so the session was revoked and the app returned to the sign-in screen. The
/// second attempt was refused as a code nobody had asked for.
///
/// So: the secure store is tried first and kept for as long as it works. The
/// first failure switches this process over to `localStorage` for good. That
/// is a real reduction in protection at rest, and it is confined to the one
/// case where the alternative is no session at all — a browser that has
/// already refused to encrypt, on an origin whose traffic is in the clear
/// anyway. Under https, and on Android and iOS, nothing here is reached.
class AppStorage {
  const AppStorage(this._secure);

  final FlutterSecureStorage _secure;

  /// Both apps are served from the panel's single origin, so an unprefixed key
  /// would let whichever signed in last hand its token to the other.
  static const _namespace = 'shiraztyres_customer';

  /// Settled on first use and then left alone: whether this build can reach
  /// an encrypted store. A failure part-way through still switches it over.
  static bool? _plain;

  static bool get _secureIsUnusable => _plain ??= plainStoreRequired();

  Future<String?> read({required String key}) async {
    if (!_secureIsUnusable) {
      try {
        return await _secure.read(key: key);
      } catch (_) {
        _plain = true;
      }
    }
    return plainRead('${_namespace}_$key');
  }

  Future<void> write({required String key, required String value}) async {
    if (!_secureIsUnusable) {
      try {
        return await _secure.write(key: key, value: value);
      } catch (_) {
        _plain = true;
      }
    }
    plainWrite('${_namespace}_$key', value);
  }

  Future<void> delete({required String key}) async {
    if (!_secureIsUnusable) {
      try {
        return await _secure.delete(key: key);
      } catch (_) {
        _plain = true;
      }
    }
    plainDelete('${_namespace}_$key');
  }
}
