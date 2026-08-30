import 'json.dart';

class OtpChallenge {
  const OtpChallenge({
    required this.expiresAt,
    required this.resendAfterSeconds,
    required this.debugCode,
  });

  factory OtpChallenge.fromJson(Map<String, dynamic> json) => OtpChallenge(
        expiresAt: asDate(json['expires_at']),
        resendAfterSeconds: asInt(json['resend_after_seconds']),
        // Only ever present while the backend runs SMS_PROVIDER=mock.
        debugCode: asString(json['debug_code']),
      );

  final DateTime? expiresAt;
  final int resendAfterSeconds;
  final String debugCode;
}
