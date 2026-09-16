import 'json.dart';
import 'vehicle.dart';

/// A car the customer has kept, plus whatever they decided about its tyre size.
///
/// Section 4.3 keeps both figures apart on purpose: what the lookup said, and
/// what the customer typed instead. The garage shows which of the two is going
/// on the van, and who is answerable if it is wrong.
class SavedVehicle {
  const SavedVehicle({
    required this.id,
    required this.vehicle,
    required this.nickname,
    required this.isPrimary,
    required this.confirmationPath,
    required this.lookedUpTyreSize,
    required this.customerTyreSize,
    required this.effectiveTyreSize,
    required this.confirmedAt,
  });

  factory SavedVehicle.fromJson(Map<String, dynamic> json) => SavedVehicle(
        id: asInt(json['id']),
        vehicle: Vehicle.fromJson(asMap(json['vehicle'])),
        nickname: asString(json['nickname']),
        isPrimary: json['is_primary'] == true,
        confirmationPath: asString(json['confirmation_path']),
        lookedUpTyreSize: asString(json['looked_up_tyre_size']),
        customerTyreSize: asString(json['customer_tyre_size']),
        effectiveTyreSize: asString(json['effective_tyre_size']),
        confirmedAt: asDate(json['confirmed_at']),
      );

  final int id;
  final Vehicle vehicle;
  final String nickname;
  final bool isPrimary;
  final String confirmationPath;
  final String lookedUpTyreSize;
  final String customerTyreSize;
  final String effectiveTyreSize;
  final DateTime? confirmedAt;

  String get title => nickname.isNotEmpty ? nickname : vehicle.title;

  String get plate => vehicle.label;

  /// The customer typed a size over the manufacturer's, and owns the outcome.
  bool get sizeWasOverridden => confirmationPath == 'overridden';

  bool get hasSize => effectiveTyreSize.isNotEmpty;
}
