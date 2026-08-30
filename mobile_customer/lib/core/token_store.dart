import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWTs live in the platform keystore, never in shared preferences.
class TokenStore {
  const TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessKey = 'st_access';
  static const _refreshKey = 'st_refresh';

  Future<String?> readAccess() => _storage.read(key: _accessKey);

  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
