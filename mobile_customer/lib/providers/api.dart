import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_api.dart';
import '../api/dev_accounts_api.dart';
import '../api/device_api.dart';
import '../api/job_api.dart';
import '../api/vehicle_api.dart';
import '../core/api_client.dart';
import '../core/job_cache.dart';
import '../core/secure_storage.dart';
import '../core/token_store.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => const TokenStore(appSecureStorage));

/// The last call-out this device saw, so a cold start with no signal still
/// opens on it.
final jobCacheProvider = Provider<JobCache>((ref) => const JobCache(appSecureStorage));

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
final vehicleApiProvider = Provider<VehicleApi>((ref) => VehicleApi(ref.watch(apiClientProvider)));

final devAccountsApiProvider =
    Provider<DevAccountsApi>((ref) => DevAccountsApi(ref.watch(apiClientProvider)));

/// The development sign-in list. Fetched once per app start; a failure resolves
/// to an empty list rather than an error, so the sign-in screen never breaks
/// because a convenience could not load.
final devAccountsProvider = FutureProvider<DevAccounts>(
  (ref) => ref.watch(devAccountsApiProvider).fetch(),
);
