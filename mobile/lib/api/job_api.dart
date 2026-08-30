import '../core/api_client.dart';
import '../models/invoice.dart';
import '../models/job.dart';
import '../models/json.dart';
import '../models/offer.dart';
import '../models/paginated.dart';

/// Offers, the job itself, and the invoice built on site.
class JobApi {
  const JobApi(this._client);

  final ApiClient _client;

  Future<List<Offer>> offers() async {
    final data = await _client.get('/driver/offers');
    final list = data is List ? data : (asMap(data)['results'] as List? ?? const []);
    return list.map((item) => Offer.fromJson(asMap(item))).toList();
  }

  Future<Paginated<Job>> jobs({String? status}) async {
    final data = await _client.get(
      '/driver/jobs',
      query: <String, dynamic>{if (status != null) 'status': status},
    );
    return Paginated<Job>.fromJson(data, Job.fromJson);
  }

  Future<Job> job(int id) async => Job.fromJson(asMap(await _client.get('/driver/jobs/$id')));

  Future<Job> accept(int id) async =>
      Job.fromJson(asMap(await _client.post('/driver/jobs/$id/accept')));

  /// Section 6.3 — rejecting is a first-class answer in both dispatch modes, and
  /// escalates immediately rather than waiting out the timeout.
  Future<void> reject(int id, {String reason = ''}) =>
      _client.post('/driver/jobs/$id/reject', body: <String, String>{'reason': reason});

  Future<Job> setStatus(int id, String status, {String note = ''}) async {
    final data = await _client.post(
      '/driver/jobs/$id/status',
      body: <String, String>{'status': status, if (note.isNotEmpty) 'note': note},
    );
    return Job.fromJson(asMap(data));
  }

  /// Section 9.3 — the car does not always match what was recorded.
  Future<Job> correctTyre(int id, String tyreSize, {String note = ''}) async {
    final data = await _client.post(
      '/driver/jobs/$id/correct-tyre',
      body: <String, String>{'tyre_size': tyreSize, if (note.isNotEmpty) 'note': note},
    );
    return Job.fromJson(asMap(data));
  }

  Future<List<ServiceItem>> priceList() async {
    final data = await _client.get('/driver/service-items');
    final list = data is List ? data : (asMap(data)['results'] as List? ?? const []);
    return list.map((item) => ServiceItem.fromJson(asMap(item))).toList();
  }

  Future<Invoice> addLine(
    int jobId, {
    int? serviceItemId,
    String description = '',
    String? unitPrice,
    String quantity = '1',
    String kind = 'part',
  }) async {
    final data = await _client.post(
      '/driver/jobs/$jobId/invoice/lines',
      body: <String, dynamic>{
        if (serviceItemId != null) 'service_item_id': serviceItemId,
        if (description.isNotEmpty) 'description': description,
        if (unitPrice != null) 'unit_price': unitPrice,
        'quantity': quantity,
        'kind': kind,
      },
    );
    return Invoice.fromJson(asMap(data));
  }

  Future<Invoice> removeLine(int jobId, int lineId) async {
    final data = await _client.delete('/driver/jobs/$jobId/invoice/lines/$lineId');
    return Invoice.fromJson(asMap(data));
  }

  /// Section 7.1 steps 5 and 6: take the payment, close the job.
  Future<Job> complete(int jobId, {String paymentMethod = '', String reference = ''}) async {
    final data = await _client.post(
      '/driver/jobs/$jobId/complete',
      body: <String, String>{
        if (paymentMethod.isNotEmpty) 'payment_method': paymentMethod,
        if (reference.isNotEmpty) 'payment_reference': reference,
      },
    );
    return Job.fromJson(asMap(data));
  }
}
