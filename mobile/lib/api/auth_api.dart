import '../core/api_client.dart';
import '../models/driver.dart';
import '../models/json.dart';
import '../models/otp_challenge.dart';

/// Driver sign-in (specification 8.1 step 1). The OTP endpoint is shared with the
/// customer surfaces; the `purpose` is what keeps the two apart.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<OtpChallenge> requestCode(String phone) async {
    final data = await _client.post(
      '/auth/otp/request',
      body: <String, String>{'phone': phone, 'purpose': 'driver'},
    );
    return OtpChallenge.fromJson(asMap(data));
  }

  Future<DriverSession> verify({required String phone, required String code, String name = ''}) async {
    final data = await _client.post(
      '/auth/driver/otp/verify',
      body: <String, String>{'phone': phone, 'code': code, if (name.isNotEmpty) 'name': name},
    );
    final map = asMap(data);
    return DriverSession(
      access: asString(map['access']),
      refresh: asString(map['refresh']),
      isNew: map['is_new_driver'] == true,
      driver: Driver.fromJson(asMap(map['driver'])),
    );
  }
}

class DriverSession {
  const DriverSession({
    required this.access,
    required this.refresh,
    required this.isNew,
    required this.driver,
  });

  final String access;
  final String refresh;
  final bool isNew;
  final Driver driver;
}
