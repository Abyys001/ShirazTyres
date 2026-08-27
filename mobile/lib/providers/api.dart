import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/auth_api.dart';
import '../api/booking_api.dart';
import '../api/device_api.dart';
import '../api/vehicle_api.dart';
import '../core/api_client.dart';
import '../core/token_store.dart';

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ),
);

/// Bumped when a refresh fails. Deliberately depends on nothing: the auth
/// controller listens to it, so the client can report a dead session without
/// the two forming a dependency cycle.
final sessionRevokedProvider = StateProvider<int>((ref) => 0);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(tokenStoreProvider),
    onAuthLost: () => ref.read(sessionRevokedProvider.notifier).state++,
  );
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
final bookingApiProvider = Provider<BookingApi>((ref) => BookingApi(ref.watch(apiClientProvider)));
final vehicleApiProvider = Provider<VehicleApi>((ref) => VehicleApi(ref.watch(apiClientProvider)));
final deviceApiProvider = Provider<DeviceApi>((ref) => DeviceApi(ref.watch(apiClientProvider)));
