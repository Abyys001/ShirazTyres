import 'dart:io' show Platform;

import '../core/api_client.dart';

class DeviceApi {
  const DeviceApi(this._client);

  final ApiClient _client;

  Future<void> register(String token) => _client.post(
        '/devices',
        body: <String, String>{
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );

  /// Called on sign-out so the shop stops pushing to a handset that logged out.
  Future<void> deregister(String token) =>
      _client.delete('/devices', body: <String, String>{'token': token});
}
