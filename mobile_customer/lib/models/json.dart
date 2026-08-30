/// Null-tolerant readers — the API omits blank optional fields rather than
/// sending nulls, and a missing field must never crash a call-out screen.
String asString(dynamic value) => value == null ? '' : '$value';

int asInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

double? asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

DateTime? asDate(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

List<String> asStringList(dynamic value) =>
    value is List ? value.map((item) => '$item').where((item) => item.isNotEmpty).toList() : <String>[];

Map<String, dynamic> asMap(dynamic value) =>
    value is Map ? value.map((key, item) => MapEntry('$key', item)) : <String, dynamic>{};
