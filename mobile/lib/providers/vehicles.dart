import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/driver.dart';
import '../models/vehicle.dart';
import 'api.dart';
import 'auth.dart';

/// The plate the lookup tool is showing, or empty for "nothing looked up yet".
final plateQueryProvider = StateProvider<String>((ref) => '');

/// The answer for [plateQueryProvider]. A family keyed on the plate means a
/// registration checked twice in a shift is answered from what is already in
/// hand rather than from another round trip.
final plateLookupProvider = FutureProvider.family<Vehicle, String>(
  (ref, plate) => ref.read(driverApiProvider).lookupPlate(plate),
);

/// The driver's own vehicles.
///
/// `/driver/me` already carries the same list, in the same shape, and a cold
/// start has it before this screen is ever opened — so the profile is the
/// source and this only asks the API when there is no profile to read.
final myVehiclesProvider =
    AsyncNotifierProvider<MyVehiclesController, List<DriverVehicle>>(
  MyVehiclesController.new,
);

class MyVehiclesController extends AsyncNotifier<List<DriverVehicle>> {
  @override
  Future<List<DriverVehicle>> build() async {
    final known = ref.watch(currentDriverProvider)?.vehicles;
    if (known != null && known.isNotEmpty) return known;
    return ref.read(driverApiProvider).myVehicles();
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(() => ref.read(driverApiProvider).myVehicles());
    // A failed reload must not empty a list that is already on screen.
    if (result.hasError && state.hasValue) return;
    state = result;
  }

  Future<void> add(String plate) async {
    await ref.read(driverApiProvider).addVehicle(plate);
    await _reloadEverywhere();
  }

  /// Re-asks DVLA for one car. Tax and MOT are the whole reason this screen
  /// exists, and both move without anybody touching the record.
  Future<void> recheck(int id) async {
    await ref.read(driverApiProvider).refreshVehicle(id);
    await _reloadEverywhere();
  }

  Future<void> remove(int id) async {
    await ref.read(driverApiProvider).removeVehicle(id);
    await _reloadEverywhere();
  }

  /// Refetching the profile is what refreshes this list: the two share a
  /// source, and onboarding is gated on the profile's copy, so they are never
  /// allowed to disagree.
  Future<void> _reloadEverywhere() =>
      ref.read(authControllerProvider.notifier).refreshDriver();
}
