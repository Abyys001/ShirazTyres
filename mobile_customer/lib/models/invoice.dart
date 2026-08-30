import 'json.dart';

class Invoice {
  const Invoice({
    required this.id,
    required this.status,
    required this.statusDisplay,
    required this.currency,
    required this.vatRate,
    required this.subtotal,
    required this.vatAmount,
    required this.total,
    required this.isEditable,
    required this.lines,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
        id: asInt(json['id']),
        status: asString(json['status']),
        statusDisplay: asString(json['status_display']),
        currency: asString(json['currency']),
        vatRate: asString(json['vat_rate']),
        subtotal: asString(json['subtotal']),
        vatAmount: asString(json['vat_amount']),
        total: asString(json['total']),
        isEditable: json['is_editable'] == true,
        lines: (json['lines'] as List? ?? const [])
            .map((item) => InvoiceLine.fromJson(asMap(item)))
            .toList(),
      );

  final int id;
  final String status;
  final String statusDisplay;
  final String currency;
  final String vatRate;
  final String subtotal;
  final String vatAmount;
  final String total;
  final bool isEditable;
  final List<InvoiceLine> lines;
}

class InvoiceLine {
  const InvoiceLine({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.isSystem,
  });

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
        id: asInt(json['id']),
        description: asString(json['description']),
        quantity: asString(json['quantity']),
        unitPrice: asString(json['unit_price']),
        lineTotal: asString(json['line_total']),
        isSystem: json['is_system'] == true,
      );

  final int id;
  final String description;
  final String quantity;
  final String unitPrice;
  final String lineTotal;

  /// The call-out fee. Set by the office, not removable on site (section 7.1).
  final bool isSystem;
}

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.code,
    required this.name,
    required this.kind,
    required this.unitPrice,
    required this.unit,
  });

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
        id: asInt(json['id']),
        code: asString(json['code']),
        name: asString(json['name']),
        kind: asString(json['kind']),
        unitPrice: asString(json['unit_price']),
        unit: asString(json['unit']),
      );

  final int id;
  final String code;
  final String name;
  final String kind;
  final String unitPrice;
  final String unit;
}
