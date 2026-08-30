import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/auth_api.dart';
import '../api/device_api.dart';
import '../api/job_api.dart';
import '../core/api_client.dart';
import '../core/token_store.dart';

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ),
);

/// Bumped when a refresh fails, so the auth controller can react without the
/// client and the controller depending on each other.
final sessionRevokedProvider = StateProvider<int>((ref) => 0);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(tokenStoreProvider),
    onAuthLost: () => ref.read(sessionRevokedProvider.notifier).state++,
  );
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
final jobApiProvider = Provider<JobApi>((ref) => JobApi(ref.watch(apiClientProvider)));
final deviceApiProvider = Provider<DeviceApi>((ref) => DeviceApi(ref.watch(apiClientProvider)));
