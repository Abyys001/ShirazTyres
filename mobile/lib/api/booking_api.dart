import '../core/api_client.dart';
import '../models/booking.dart';
import '../models/json.dart';
import '../models/paginated.dart';

class BookingApi {
  const BookingApi(this._client);

  final ApiClient _client;

  Future<Paginated<Booking>> myBookings({int page = 1}) async {
    final data = await _client.get('/my/bookings', query: <String, dynamic>{'page': page});
    return Paginated<Booking>.fromJson(data, Booking.fromJson);
  }

  Future<Booking> booking(int id) async =>
      Booking.fromJson(asMap(await _client.get('/my/bookings/$id')));

  Future<Booking> create({
    required String issueType,
    required String contactPhone,
    String plate = '',
    String contactName = '',
    String contactEmail = '',
    String description = '',
    String tyreSize = '',
    String locationText = '',
    double? latitude,
    double? longitude,
  }) async {
    final data = await _client.post(
      '/my/bookings/create',
      body: <String, dynamic>{
        'issue_type': issueType,
        'contact_phone': contactPhone,
        if (plate.isNotEmpty) 'plate': plate,
        if (contactName.isNotEmpty) 'contact_name': contactName,
        if (contactEmail.isNotEmpty) 'contact_email': contactEmail,
        if (description.isNotEmpty) 'description': description,
        if (tyreSize.isNotEmpty) 'tyre_size': tyreSize,
        if (locationText.isNotEmpty) 'location_text': locationText,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
    );
    return Booking.fromJson(asMap(data));
  }
}
