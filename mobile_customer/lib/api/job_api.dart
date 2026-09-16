import '../core/api_client.dart';
import '../models/damaged_tyre.dart';
import '../models/job.dart';
import '../models/json.dart';
import '../models/paginated.dart';
import '../models/public_config.dart';
import '../models/vehicle.dart';

class JobApi {
  const JobApi(this._client);

  final ApiClient _client;

  Future<PublicConfig> config() async =>
      PublicConfig.fromJson(asMap(await _client.get('/public/config')));

  /// Section 4.2 — DVLA details plus the manufacturer's tyre specification.
  Future<Vehicle> lookup(String plate) async {
    final bare = plate.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return Vehicle.fromJson(asMap(await _client.get('/public/vehicle-lookup/$bare')));
  }

  /// Section 4.4 — asked the moment a position is captured, so a motorist
  /// outside the area finds out before filling anything else in.
  Future<Coverage> coverage({required double latitude, required double longitude}) async {
    final data = await _client.post(
      '/public/coverage',
      body: <String, String>{
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
      },
    );
    return Coverage.fromJson(asMap(data));
  }

  Future<Paginated<CustomerJob>> myJobs() async =>
      Paginated<CustomerJob>.fromJson(await _client.get('/my/jobs'), CustomerJob.fromJson);

  /// The same page, undecoded, so it can be cached verbatim and read back by a
  /// cold start that has no signal.
  Future<List<Map<String, dynamic>>> myJobsRaw() async {
    final data = await _client.get('/my/jobs');
    final results = data is List ? data : asMap(data)['results'];
    return results is List ? results.map(asMap).toList() : <Map<String, dynamic>>[];
  }

  Future<CustomerJob?> active() async {
    final data = await activeRaw();
    return data == null ? null : CustomerJob.fromJson(data);
  }

  /// Undecoded, for the same reason as [myJobsRaw]. Null is a real answer here:
  /// "you have no call-out running" is worth caching too.
  Future<Map<String, dynamic>?> activeRaw() async {
    final data = asMap(await _client.get('/my/jobs/active'));
    return data['job'] == null ? null : asMap(data['job']);
  }

  Future<CustomerJob> job(int id) async =>
      CustomerJob.fromJson(asMap(await _client.get('/my/jobs/$id')));

  Future<CustomerJob> submit({
    required String plate,
    required String issueType,
    required String description,
    required String locationText,
    required double latitude,
    required double longitude,
    int? accuracyMetres,
    String locationSource = 'device',
    required String confirmationPath,
    required String tyreSize,
    String loadIndex = '',
    String speedRating = '',
    bool disclaimerAccepted = false,
    List<DamagedTyre> damaged = const <DamagedTyre>[],
  }) async {
    final data = await _client.post(
      '/my/jobs',
      body: <String, dynamic>{
        'source': 'app',
        if (plate.isNotEmpty) 'plate': plate,
        'issue_type': issueType,
        if (description.isNotEmpty) 'description': description,
        if (locationText.isNotEmpty) 'location_text': locationText,
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
        if (accuracyMetres != null) 'location_accuracy_m': accuracyMetres,
        // Section 4.4: the native device permission, or a pin the customer
        // dropped themselves when the phone cannot get a fix.
        'location_source': locationSource,
        'tyre_confirmation': <String, dynamic>{
          'confirmation_path': confirmationPath,
          'tyre_size': tyreSize,
          if (loadIndex.isNotEmpty) 'load_index': loadIndex,
          if (speedRating.isNotEmpty) 'speed_rating': speedRating,
          'disclaimer_accepted': disclaimerAccepted,
        },
        // Omitted rather than sent empty: the API tells the technician the
        // difference between "no damage reported" and "the customer skipped it".
        if (damaged.isNotEmpty)
          'damaged_positions': damaged.map((tyre) => tyre.toJson()).toList(),
      },
    );
    return CustomerJob.fromJson(asMap(data));
  }

  Future<CustomerJob> cancel(int id, {String reason = ''}) async {
    final data = await _client.post(
      '/my/jobs/$id/cancel',
      body: <String, String>{if (reason.isNotEmpty) 'reason': reason},
    );
    return CustomerJob.fromJson(asMap(data));
  }
}
