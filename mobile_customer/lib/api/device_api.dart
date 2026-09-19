import 'package:flutter/foundation.dart';

import '../core/api_client.dart';

class DeviceApi {
  const DeviceApi(this._client);

  final ApiClient _client;

  Future<void> register(String token) => _client.post(
        '/devices',
        body: <String, String>{
          'token': token,
          'platform': _platform,
        },
      );

  /// One of `DeviceToken.Platform` on the API, which has a `web` value for
  /// exactly this. Nothing registers yet — the push service is a no-op until
  /// Firebase is wired — but a browser must not enrol as a handset, or the
  /// first real push will be aimed at a device that cannot receive it.
  static String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  /// Called on sign-out so the shop stops pushing to a handset that logged out.
  Future<void> deregister(String token) =>
      _client.delete('/devices', body: <String, String>{'token': token});
}
