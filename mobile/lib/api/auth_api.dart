import '../core/api_client.dart';
import '../models/driver.dart';
import '../models/json.dart';
import '../models/otp_challenge.dart';

class VerifiedSession {
  const VerifiedSession({
    required this.access,
    required this.refresh,
    required this.driver,
    required this.isNewDriver,
  });

  final String access;
  final String refresh;
  final Driver driver;
  final bool isNewDriver;
}

class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<OtpChallenge> requestOtp(String phone, {String purpose = 'login'}) async {
    final data = await _client.post(
      '/auth/otp/request',
      body: <String, String>{'phone': phone, 'purpose': purpose},
    );
    return OtpChallenge.fromJson(asMap(data));
  }

  Future<VerifiedSession> verifyOtp(
    String phone,
    String code, {
    String name = '',
    String email = '',
  }) async {
    final data = asMap(
      await _client.post(
        '/auth/otp/verify',
        body: <String, String>{
          'phone': phone,
          'code': code,
          if (name.isNotEmpty) 'name': name,
          if (email.isNotEmpty) 'email': email,
        },
      ),
    );
    return VerifiedSession(
      access: asString(data['access']),
      refresh: asString(data['refresh']),
      driver: Driver.fromJson(asMap(data['driver'])),
      isNewDriver: data['is_new_driver'] == true,
    );
  }

  Future<Driver> me() async => Driver.fromJson(asMap(await _client.get('/drivers/me')));

  Future<Driver> updateMe({String? name, String? email}) async {
    final data = await _client.patch(
      '/drivers/me',
      body: <String, String>{
        if (name != null) 'name': name,
        if (email != null) 'email': email,
      },
    );
    return Driver.fromJson(asMap(data));
  }
}
