import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/saved_vehicle.dart';
import 'api.dart';

/// The saved cars. Small enough to hold whole and re-fetch after every change,
/// which is cheaper than keeping two copies of the truth in step.
final savedVehiclesProvider =
    AsyncNotifierProvider<SavedVehicleController, List<SavedVehicle>>(SavedVehicleController.new);

class SavedVehicleController extends AsyncNotifier<List<SavedVehicle>> {
  @override
  Future<List<SavedVehicle>> build() => ref.read(vehicleApiProvider).mine();

  Future<SavedVehicle> add(String plate, {String nickname = ''}) async {
    final saved = await ref.read(vehicleApiProvider).add(plate, nickname: nickname);
    await _reload();
    return saved;
  }

  Future<void> rename(int id, String nickname) async {
    await ref.read(vehicleApiProvider).update(id, nickname: nickname);
    await _reload();
  }

  Future<void> makePrimary(int id) async {
    await ref.read(vehicleApiProvider).update(id, isPrimary: true);
    await _reload();
  }

  Future<void> remove(int id) async {
    await ref.read(vehicleApiProvider).remove(id);
    await _reload();
  }

  Future<void> confirmTyre(
    int id, {
    required String confirmationPath,
    String tyreSize = '',
    bool disclaimerAccepted = false,
  }) async {
    await ref.read(vehicleApiProvider).confirmTyre(
          id,
          confirmationPath: confirmationPath,
          tyreSize: tyreSize,
          disclaimerAccepted: disclaimerAccepted,
        );
    await _reload();
  }

  Future<void> refresh() => _reload();

  /// Keeps the list on screen while the new one loads: a garage that blinks out
  /// after every rename reads as though something went wrong.
  Future<void> _reload() async {
    final next = await AsyncValue.guard(() => ref.read(vehicleApiProvider).mine());
    if (next.hasError && state.hasValue) return;
    state = next;
  }
}
