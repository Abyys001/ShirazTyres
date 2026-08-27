import '../core/api_client.dart';
import '../models/json.dart';
import '../models/vehicle.dart';

class SavedVehicle {
  const SavedVehicle({
    required this.id,
    required this.vehicle,
    required this.nickname,
    required this.isPrimary,
  });

  factory SavedVehicle.fromJson(Map<String, dynamic> json) => SavedVehicle(
        id: asInt(json['id']),
        vehicle: Vehicle.fromJson(asMap(json['vehicle'])),
        nickname: asString(json['nickname']),
        isPrimary: json['is_primary'] == true,
      );

  final int id;
  final Vehicle vehicle;
  final String nickname;
  final bool isPrimary;

  String get label => nickname.isNotEmpty ? nickname : vehicle.label;
}

class VehicleApi {
  const VehicleApi(this._client);

  final ApiClient _client;

  Future<Vehicle> lookup(String plate) async =>
      Vehicle.fromJson(asMap(await _client.get('/vehicle-lookup/$plate')));

  Future<List<SavedVehicle>> myVehicles() async {
    final data = await _client.get('/my-vehicles');
    final rows = data is Map ? data['results'] : data;
    return rows is List
        ? rows.map((row) => SavedVehicle.fromJson(asMap(row))).toList()
        : <SavedVehicle>[];
  }

  Future<SavedVehicle> save(String plate, {String nickname = '', bool isPrimary = false}) async {
    final data = await _client.post(
      '/my-vehicles',
      body: <String, dynamic>{
        'plate': plate,
        if (nickname.isNotEmpty) 'nickname': nickname,
        'is_primary': isPrimary,
      },
    );
    return SavedVehicle.fromJson(asMap(data));
  }

  Future<void> remove(int savedVehicleId) => _client.delete('/my-vehicles/$savedVehicleId');

  /// The driver telling us the size beats anything the lookup API guessed.
  Future<Vehicle> confirmTyreSize(int savedVehicleId, String tyreSize) async {
    final data = await _client.post(
      '/my-vehicles/$savedVehicleId/confirm-tyre',
      body: <String, String>{'tyre_size': tyreSize},
    );
    return Vehicle.fromJson(asMap(data));
  }
}
