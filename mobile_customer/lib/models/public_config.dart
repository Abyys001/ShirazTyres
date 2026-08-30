import 'json.dart';

/// What the app needs before anyone signs in — issue types, the call-out fee,
/// business hours and the out-of-area wording (specification 12).
class PublicConfig {
  const PublicConfig({
    required this.issueTypes,
    required this.calloutFee,
    required this.calloutFeeEnabled,
    required this.vatRate,
    required this.currency,
    required this.isOpen,
    required this.outOfHoursBehaviour,
    required this.outOfHoursMessage,
    required this.outOfAreaMessage,
  });

  factory PublicConfig.fromJson(Map<String, dynamic> json) => PublicConfig(
        issueTypes: (json['issue_types'] as List? ?? const [])
            .map((item) => IssueType.fromJson(asMap(item)))
            .toList(),
        calloutFee: asString(json['callout_fee']),
        calloutFeeEnabled: json['callout_fee_enabled'] == true,
        vatRate: asString(json['vat_rate']),
        currency: asString(json['currency']),
        isOpen: json['is_open'] == true,
        outOfHoursBehaviour: asString(json['out_of_hours_behaviour']),
        outOfHoursMessage: asString(json['out_of_hours_message']),
        outOfAreaMessage: asString(json['out_of_area_message']),
      );

  final List<IssueType> issueTypes;
  final String calloutFee;
  final bool calloutFeeEnabled;
  final String vatRate;
  final String currency;
  final bool isOpen;
  final String outOfHoursBehaviour;
  final String outOfHoursMessage;
  final String outOfAreaMessage;

  bool get refusingOutOfHours => !isOpen && outOfHoursBehaviour == 'refuse';
}

class IssueType {
  const IssueType({required this.value, required this.label});

  factory IssueType.fromJson(Map<String, dynamic> json) =>
      IssueType(value: asString(json['value']), label: asString(json['label']));

  final String value;
  final String label;
}

class Coverage {
  const Coverage({required this.covered, required this.area, required this.message});

  factory Coverage.fromJson(Map<String, dynamic> json) => Coverage(
        covered: json['covered'] == true,
        area: asString(json['area']),
        message: asString(json['message']),
      );

  final bool covered;
  final String area;
  final String message;
}
