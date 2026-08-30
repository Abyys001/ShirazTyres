import 'invoice.dart';
import 'json.dart';
import 'vehicle.dart';

/// The ten statuses of section 5, as the driver app sees them.
class JobStatus {
  const JobStatus._();

  static const assigned = 'assigned';
  static const accepted = 'accepted';
  static const enRoute = 'en_route';
  static const arrived = 'arrived';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  /// The forward path a technician walks, in order.
  static const flow = <String>[enRoute, arrived, inProgress];

  static String label(String status) {
    switch (status) {
      case assigned:
        return 'Assigned to you';
      case accepted:
        return 'Accepted';
      case enRoute:
        return 'On the way';
      case arrived:
        return 'Arrived';
      case inProgress:
        return 'Working';
      case completed:
        return 'Completed';
      case cancelled:
        return 'Cancelled';
      default:
        return status;
    }
  }

  static String actionLabel(String next) {
    switch (next) {
      case enRoute:
        return 'Start driving';
      case arrived:
        return "I'm here";
      case inProgress:
        return 'Start work';
      default:
        return label(next);
    }
  }
}

class Job {
  const Job({
    required this.id,
    required this.reference,
    required this.vehicle,
    required this.plate,
    required this.contactName,
    required this.contactPhone,
    required this.issueLabel,
    required this.description,
    required this.tyreSize,
    required this.lookedUpTyreSize,
    required this.customerTyreSize,
    required this.confirmationPath,
    required this.correctedOnSite,
    required this.locationText,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.statusDisplay,
    required this.etaMinutes,
    required this.mapsUrl,
    required this.invoice,
    required this.createdAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) => Job(
        id: asInt(json['id']),
        reference: asString(json['reference']),
        vehicle: json['vehicle'] == null ? null : Vehicle.fromJson(asMap(json['vehicle'])),
        plate: asString(json['plate']),
        contactName: asString(json['contact_name']),
        contactPhone: asString(json['contact_phone']),
        issueLabel: asString(json['issue_label']),
        description: asString(json['description']),
        tyreSize: asString(json['tyre_size']),
        lookedUpTyreSize: asString(json['looked_up_tyre_size']),
        customerTyreSize: asString(json['customer_tyre_size']),
        confirmationPath: asString(json['tyre_confirmation_path']),
        correctedOnSite: json['tyre_corrected_on_site'] == true,
        locationText: asString(json['location_text']),
        latitude: asDouble(json['latitude']),
        longitude: asDouble(json['longitude']),
        status: asString(json['status']),
        statusDisplay: asString(json['status_display']),
        etaMinutes: json['eta_minutes'] == null ? null : asInt(json['eta_minutes']),
        mapsUrl: asString(json['maps_url']),
        invoice: json['invoice'] == null ? null : Invoice.fromJson(asMap(json['invoice'])),
        createdAt: asDate(json['created_at']),
      );

  final int id;
  final String reference;
  final Vehicle? vehicle;
  final String plate;
  final String contactName;
  final String contactPhone;
  final String issueLabel;
  final String description;
  final String tyreSize;
  final String lookedUpTyreSize;
  final String customerTyreSize;
  final String confirmationPath;
  final bool correctedOnSite;
  final String locationText;
  final double? latitude;
  final double? longitude;
  final String status;
  final String statusDisplay;
  final int? etaMinutes;
  final String mapsUrl;
  final Invoice? invoice;
  final DateTime? createdAt;

  /// Section 4.3 path B — the customer gave this size themselves and accepted
  /// responsibility for it. Worth knowing before loading the van.
  bool get sizeFromCustomer => confirmationPath == 'overridden';

  bool get isLive => status != JobStatus.completed && status != JobStatus.cancelled;

  String? get nextStatus {
    switch (status) {
      case JobStatus.accepted:
        return JobStatus.enRoute;
      case JobStatus.enRoute:
        return JobStatus.arrived;
      case JobStatus.arrived:
        return JobStatus.inProgress;
      default:
        return null;
    }
  }
}
