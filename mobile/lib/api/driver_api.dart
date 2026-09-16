import 'dart:io';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/driver.dart';
import '../models/json.dart';
import '../models/vehicle.dart';

/// Everything about the technician themselves: profile, van, documents,
/// availability and position (specification 8 and 11).
class DriverApi {
  const DriverApi(this._client);

  final ApiClient _client;

  Future<Driver> me() async => Driver.fromJson(await meRaw());

  /// The same call, undecoded, so the session can be cached verbatim and read
  /// back by a cold start that has no signal.
  Future<Map<String, dynamic>> meRaw() async => asMap(await _client.get('/driver/me'));

  Future<Driver> updateProfile({String? name, String? email, File? photo}) async {
    final form = FormData.fromMap(<String, dynamic>{
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (photo != null) 'photo': await MultipartFile.fromFile(photo.path),
    });
    return Driver.fromJson(asMap(await _client.patch('/driver/me', body: form)));
  }

  Future<Driver> setOnline(bool online) async {
    final data = await _client.post('/driver/online', body: <String, bool>{'is_online': online});
    return Driver.fromJson(asMap(data));
  }

  /// Section 8.1 step 3 — make, model and colour fill in from the plate.
  Future<DriverVehicle> addVehicle(String plate) async {
    final data = await _client.post('/driver/vehicles', body: <String, String>{'plate': plate});
    return DriverVehicle.fromJson(asMap(data));
  }

  Future<List<DriverVehicle>> myVehicles() async {
    final data = await _client.get('/driver/vehicles');
    final results = data is List ? data : asMap(data)['results'];
    return results is List
        ? results.map((item) => DriverVehicle.fromJson(asMap(item))).toList()
        : <DriverVehicle>[];
  }

  /// Re-asks DVLA. Tax and MOT move on their own; nothing else about a van does.
  Future<DriverVehicle> refreshVehicle(int id) async =>
      DriverVehicle.fromJson(asMap(await _client.post('/driver/vehicles/$id/refresh')));

  Future<void> removeVehicle(int id) => _client.delete('/driver/vehicles/$id');

  /// The plate tool: what the car actually is, and what tyre it takes. Its own
  /// endpoint rather than the customer app's public one, because a technician
  /// runs this a dozen times a shift.
  Future<Vehicle> lookupPlate(String plate) async {
    final bare = plate.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return Vehicle.fromJson(asMap(await _client.get('/driver/vehicle-lookup/$bare')));
  }

  Future<DriverDocument> uploadDocument({
    required String documentType,
    required DateTime expiryDate,
    required File file,
  }) async {
    final form = FormData.fromMap(<String, dynamic>{
      'document_type': documentType,
      'expiry_date': expiryDate.toIso8601String().substring(0, 10),
      'file': await MultipartFile.fromFile(file.path),
    });
    return DriverDocument.fromJson(asMap(await _client.post('/driver/documents', body: form)));
  }

  /// One fix, or a flushed buffer of them after a signal drop.
  Future<void> sendLocations(List<Map<String, dynamic>> points) async {
    if (points.isEmpty) return;
    await _client.post(
      '/driver/location',
      body: points.length == 1 ? points.first : <String, dynamic>{'points': points},
    );
  }
}
