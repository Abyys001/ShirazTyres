import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/vehicle_api.dart';
import '../models/vehicle.dart';
import 'api.dart';
import 'auth.dart';

class MyVehiclesController extends AsyncNotifier<List<SavedVehicle>> {
  @override
  Future<List<SavedVehicle>> build() async {
    if (!ref.watch(authControllerProvider).isSignedIn) {
      return const <SavedVehicle>[];
    }
    return ref.read(vehicleApiProvider).myVehicles();
  }

  Future<SavedVehicle> add(String plate, {String nickname = ''}) async {
    final saved = await ref.read(vehicleApiProvider).save(
          plate,
          nickname: nickname,
          isPrimary: (state.valueOrNull ?? const <SavedVehicle>[]).isEmpty,
        );
    ref.invalidateSelf();
    return saved;
  }

  Future<void> remove(int id) async {
    await ref.read(vehicleApiProvider).remove(id);
    ref.invalidateSelf();
  }

  Future<Vehicle> confirmTyreSize(int savedVehicleId, String tyreSize) async {
    final vehicle = await ref.read(vehicleApiProvider).confirmTyreSize(savedVehicleId, tyreSize);
    ref.invalidateSelf();
    return vehicle;
  }
}

final myVehiclesProvider =
    AsyncNotifierProvider<MyVehiclesController, List<SavedVehicle>>(MyVehiclesController.new);

final primaryVehicleProvider = Provider<SavedVehicle?>((ref) {
  final saved = ref.watch(myVehiclesProvider).valueOrNull ?? const <SavedVehicle>[];
  if (saved.isEmpty) return null;
  for (final vehicle in saved) {
    if (vehicle.isPrimary) return vehicle;
  }
  return saved.first;
});

/// One-off plate lookup used by the "new request" screen.
final plateLookupProvider = FutureProvider.autoDispose.family<Vehicle, String>(
  (ref, plate) => ref.watch(vehicleApiProvider).lookup(plate),
);
