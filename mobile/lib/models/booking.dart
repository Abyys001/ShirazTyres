import 'json.dart';
import 'vehicle.dart';

class BookingStatus {
  const BookingStatus._();

  static const received = 'received';
  static const assigned = 'assigned';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static const labels = <String, String>{
    received: 'Received',
    assigned: 'Fitter assigned',
    inProgress: 'On the way',
    completed: 'Completed',
    cancelled: 'Cancelled',
  };

  static const open = <String>{received, assigned, inProgress};

  static String label(String status) => labels[status] ?? status;
}

class IssueType {
  const IssueType._();

  static const labels = <String, String>{
    'puncture': 'Puncture',
    'blowout': 'Blowout',
    'tyre_damage': 'Tyre damage',
    'wheel_change': 'Wheel change',
    'other': 'Something else',
  };

  static List<String> get values => labels.keys.toList();

  static String label(String issue) => labels[issue] ?? issue;
}

class BookingStatusEvent {
  const BookingStatusEvent({
    required this.id,
    required this.fromStatus,
    required this.toStatus,
    required this.note,
    required this.changedByName,
    required this.createdAt,
  });

  factory BookingStatusEvent.fromJson(Map<String, dynamic> json) => BookingStatusEvent(
        id: asInt(json['id']),
        fromStatus: asString(json['from_status']),
        toStatus: asString(json['to_status']),
        note: asString(json['note']),
        changedByName: asString(json['changed_by_name']),
        createdAt: asDate(json['created_at']),
      );

  final int id;
  final String fromStatus;
  final String toStatus;
  final String note;
  final String changedByName;
  final DateTime? createdAt;
}

class Booking {
  const Booking({
    required this.id,
    required this.reference,
    required this.vehicle,
    required this.plate,
    required this.contactName,
    required this.contactPhone,
    required this.issueType,
    required this.issueDisplay,
    required this.description,
    required this.tyreSize,
    required this.locationText,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.statusDisplay,
    required this.createdAt,
    required this.assignedAt,
    required this.completedAt,
    required this.mapsUrl,
    required this.statusEvents,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    final vehicleJson = json['vehicle'];
    final events = json['status_events'];
    return Booking(
      id: asInt(json['id']),
      reference: asString(json['reference']),
      vehicle: vehicleJson is Map ? Vehicle.fromJson(asMap(vehicleJson)) : null,
      plate: asString(json['plate']),
      contactName: asString(json['contact_name']),
      contactPhone: asString(json['contact_phone']),
      issueType: asString(json['issue_type']),
      issueDisplay: asString(json['issue_display']),
      description: asString(json['description']),
      tyreSize: asString(json['tyre_size']),
      locationText: asString(json['location_text']),
      latitude: asDouble(json['latitude']),
      longitude: asDouble(json['longitude']),
      status: asString(json['status']),
      statusDisplay: asString(json['status_display']),
      createdAt: asDate(json['created_at']),
      assignedAt: asDate(json['assigned_at']),
      completedAt: asDate(json['completed_at']),
      mapsUrl: asString(json['maps_url']),
      statusEvents: events is List
          ? events.map((event) => BookingStatusEvent.fromJson(asMap(event))).toList()
          : const <BookingStatusEvent>[],
    );
  }

  final int id;
  final String reference;
  final Vehicle? vehicle;
  final String plate;
  final String contactName;
  final String contactPhone;
  final String issueType;
  final String issueDisplay;
  final String description;
  final String tyreSize;
  final String locationText;
  final double? latitude;
  final double? longitude;
  final String status;
  final String statusDisplay;
  final DateTime? createdAt;
  final DateTime? assignedAt;
  final DateTime? completedAt;
  final String mapsUrl;
  final List<BookingStatusEvent> statusEvents;

  bool get isOpen => BookingStatus.open.contains(status);

  String get statusLabel => statusDisplay.isNotEmpty ? statusDisplay : BookingStatus.label(status);

  String get issueLabel => issueDisplay.isNotEmpty ? issueDisplay : IssueType.label(issueType);

  String get whereLabel {
    if (locationText.isNotEmpty) return locationText;
    if (latitude != null && longitude != null) {
      return '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
    }
    return 'Location not given';
  }
}
