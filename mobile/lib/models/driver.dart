import 'json.dart';

class Driver {
  const Driver({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.isPhoneVerified,
  });

  factory Driver.fromJson(Map<String, dynamic> json) => Driver(
        id: asInt(json['id']),
        name: asString(json['name']),
        phone: asString(json['phone']),
        email: asString(json['email']),
        isPhoneVerified: json['is_phone_verified'] == true,
      );

  final int id;
  final String name;
  final String phone;
  final String email;
  final bool isPhoneVerified;

  String get displayName => name.isNotEmpty ? name : phone;
}
