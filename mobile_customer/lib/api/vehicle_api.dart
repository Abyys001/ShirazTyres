import '../core/api_client.dart';
import '../models/json.dart';
import '../models/saved_vehicle.dart';

/// The customer's garage — `/my-vehicles`, so a repeat call-out is two taps.
class VehicleApi {
  const VehicleApi(this._client);

  final ApiClient _client;

  Future<List<SavedVehicle>> mine() async {
    final data = await _client.get('/my-vehicles');
    // The viewset is unpaginated for a list this short, but a paginated page
    // arrives as a map with `results`, so both shapes are read.
    final rows = data is List ? data : (asMap(data)['results'] as List? ?? const <dynamic>[]);
    return rows.map((row) => SavedVehicle.fromJson(asMap(row))).toList();
  }

  /// The plate is looked up server-side; an unknown registration comes back as
  /// a field error on `plate`.
  Future<SavedVehicle> add(String plate, {String nickname = ''}) async {
    final data = await _client.post(
      '/my-vehicles',
      body: <String, dynamic>{
        'plate': plate.replaceAll(RegExp('[^A-Za-z0-9]'), ''),
        if (nickname.isNotEmpty) 'nickname': nickname,
      },
    );
    return SavedVehicle.fromJson(asMap(data));
  }

  Future<SavedVehicle> update(int id, {String? nickname, bool? isPrimary}) async {
    final data = await _client.patch(
      '/my-vehicles/$id',
      body: <String, dynamic>{
        if (nickname != null) 'nickname': nickname,
        if (isPrimary != null) 'is_primary': isPrimary,
      },
    );
    return SavedVehicle.fromJson(asMap(data));
  }

  Future<void> remove(int id) => _client.delete('/my-vehicles/$id');

  /// Section 4.3 against a saved car, so the decision carries into the next
  /// call-out instead of being made again at the roadside.
  Future<SavedVehicle> confirmTyre(
    int id, {
    required String confirmationPath,
    String tyreSize = '',
    String loadIndex = '',
    String speedRating = '',
    bool disclaimerAccepted = false,
  }) async {
    final data = await _client.post(
      '/my-vehicles/$id/confirm-tyre',
      body: <String, dynamic>{
        'confirmation_path': confirmationPath,
        if (tyreSize.isNotEmpty) 'tyre_size': tyreSize,
        if (loadIndex.isNotEmpty) 'load_index': loadIndex,
        if (speedRating.isNotEmpty) 'speed_rating': speedRating,
        'disclaimer_accepted': disclaimerAccepted,
      },
    );
    return SavedVehicle.fromJson(asMap(data));
  }
}
