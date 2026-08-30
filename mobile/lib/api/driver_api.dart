import 'dart:io';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/driver.dart';
import '../models/json.dart';

/// Everything about the technician themselves: profile, van, documents,
/// availability and position (specification 8 and 11).
class DriverApi {
  const DriverApi(this._client);

  final ApiClient _client;

  Future<Driver> me() async => Driver.fromJson(asMap(await _client.get('/driver/me')));

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
