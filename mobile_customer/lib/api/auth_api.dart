import '../core/api_client.dart';
import '../models/customer.dart';
import '../models/json.dart';
import '../models/otp_challenge.dart';

/// Two sign-in routes, one account (specification 4.1).
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<OtpChallenge> requestCode(String phone) async {
    final data = await _client.post(
      '/auth/otp/request',
      body: <String, String>{'phone': phone, 'purpose': 'login'},
    );
    return OtpChallenge.fromJson(asMap(data));
  }

  Future<CustomerSession> verifyOtp({required String phone, required String code}) async {
    final data = await _client.post(
      '/auth/customer/otp/verify',
      body: <String, String>{'phone': phone, 'code': code},
    );
    return CustomerSession.fromJson(asMap(data));
  }

  /// The ID token is verified by the API against Google's keys — the app never
  /// asserts who the customer is.
  Future<CustomerSession> google(String idToken) async {
    final data = await _client.post(
      '/auth/customer/google',
      body: <String, String>{'id_token': idToken},
    );
    return CustomerSession.fromJson(asMap(data));
  }

  /// Proves a phone number for a customer who started with Google, so both
  /// routes reach the same job history.
  Future<Customer> attachPhone({required String phone, required String code}) async {
    final data = await _client.post(
      '/auth/customer/attach-phone',
      body: <String, String>{'phone': phone, 'code': code},
    );
    return Customer.fromJson(asMap(data));
  }

  Future<Customer> me() async => Customer.fromJson(asMap(await _client.get('/customers/me')));

  Future<Customer> updateMe({String? name, String? email}) async {
    final data = await _client.patch(
      '/customers/me',
      body: <String, String>{if (name != null) 'name': name, if (email != null) 'email': email},
    );
    return Customer.fromJson(asMap(data));
  }
}

class CustomerSession {
  const CustomerSession({
    required this.access,
    required this.refresh,
    required this.isNew,
    required this.customer,
  });

  factory CustomerSession.fromJson(Map<String, dynamic> json) => CustomerSession(
        access: asString(json['access']),
        refresh: asString(json['refresh']),
        isNew: json['is_new_customer'] == true,
        customer: Customer.fromJson(asMap(json['customer'])),
      );

  final String access;
  final String refresh;
  final bool isNew;
  final Customer customer;
}
