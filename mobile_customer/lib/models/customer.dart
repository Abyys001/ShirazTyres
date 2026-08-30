import 'json.dart';

/// The stranded motorist (specification section 2). Never the technician.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.photoUrl,
    required this.isPhoneVerified,
    required this.isEmailVerified,
    required this.jobCount,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: asInt(json['id']),
        name: asString(json['name']),
        phone: asString(json['phone']),
        email: asString(json['email']),
        photoUrl: asString(json['photo_url']),
        isPhoneVerified: json['is_phone_verified'] == true,
        isEmailVerified: json['is_email_verified'] == true,
        jobCount: asInt(json['job_count']),
      );

  final int id;
  final String name;
  final String phone;
  final String email;
  final String photoUrl;
  final bool isPhoneVerified;
  final bool isEmailVerified;
  final int jobCount;

  String get displayName => name.isNotEmpty ? name : (phone.isNotEmpty ? phone : email);

  /// A Google-first customer has no number yet; attaching one joins the two
  /// sign-in routes to this single account (section 4.1).
  bool get needsPhone => phone.isEmpty;
}
