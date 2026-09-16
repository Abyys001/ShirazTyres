import 'invoice.dart';
import 'json.dart';
import 'vehicle.dart';

/// Exactly the six fields section 4.6 allows a customer to see about a technician.
class AssignedDriver {
  const AssignedDriver({
    required this.firstName,
    required this.photo,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleColour,
    required this.vehiclePlate,
  });

  factory AssignedDriver.fromJson(Map<String, dynamic> json) => AssignedDriver(
        firstName: asString(json['first_name']),
        photo: asString(json['photo']),
        vehicleMake: asString(json['vehicle_make']),
        vehicleModel: asString(json['vehicle_model']),
        vehicleColour: asString(json['vehicle_colour']),
        vehiclePlate: asString(json['vehicle_plate']),
      );

  final String firstName;
  final String photo;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleColour;
  final String vehiclePlate;

  String get vehicleDescription =>
      <String>[vehicleColour, vehicleMake, vehicleModel].where((part) => part.isNotEmpty).join(' ');
}

class CustomerJob {
  const CustomerJob({
    required this.id,
    required this.reference,
    required this.vehicle,
    required this.plate,
    required this.issueLabel,
    required this.description,
    required this.tyreSize,
    required this.lookedUpTyreSize,
    required this.customerTyreSize,
    required this.confirmationPath,
    required this.locationText,
    required this.status,
    required this.statusDisplay,
    required this.driver,
    required this.etaMinutes,
    required this.etaUpdatedAt,
    required this.canCancel,
    required this.invoice,
    required this.createdAt,
    required this.timeline,
  });

  factory CustomerJob.fromJson(Map<String, dynamic> json) => CustomerJob(
        id: asInt(json['id']),
        reference: asString(json['reference']),
        vehicle: json['vehicle'] == null ? null : Vehicle.fromJson(asMap(json['vehicle'])),
        plate: asString(json['plate']),
        issueLabel: asString(json['issue_label']),
        description: asString(json['description']),
        tyreSize: asString(json['tyre_size']),
        lookedUpTyreSize: asString(json['looked_up_tyre_size']),
        customerTyreSize: asString(json['customer_tyre_size']),
        confirmationPath: asString(json['tyre_confirmation_path']),
        locationText: asString(json['location_text']),
        status: asString(json['status']),
        statusDisplay: asString(json['status_display']),
        driver: json['driver'] == null ? null : AssignedDriver.fromJson(asMap(json['driver'])),
        etaMinutes: json['eta_minutes'] == null ? null : asInt(json['eta_minutes']),
        etaUpdatedAt: asDate(json['eta_updated_at']),
        canCancel: json['can_cancel'] == true,
        invoice: json['invoice'] == null ? null : Invoice.fromJson(asMap(json['invoice'])),
        createdAt: asDate(json['created_at']),
        timeline: (json['timeline'] as List? ?? const [])
            .map((item) => TimelineEntry.fromJson(asMap(item)))
            .toList(),
      );

  final int id;
  final String reference;
  final Vehicle? vehicle;
  final String plate;
  final String issueLabel;
  final String description;
  final String tyreSize;
  final String lookedUpTyreSize;
  final String customerTyreSize;
  final String confirmationPath;
  final String locationText;
  final String status;
  final String statusDisplay;
  final AssignedDriver? driver;
  final int? etaMinutes;
  final DateTime? etaUpdatedAt;
  final bool canCancel;
  final Invoice? invoice;
  final DateTime? createdAt;
  final List<TimelineEntry> timeline;

  bool get isLive => status != 'completed' && status != 'cancelled';

  /// Rows seeded before the label was recorded come back with it empty. A
  /// headline is the largest thing on the card, so it never renders blank.
  String get issueHeadline => issueLabel.isEmpty ? 'Tyre call-out' : issueLabel;

  bool get sizeWasOverridden => confirmationPath == 'overridden';

  /// Short labels for the progress rail — the whole job in five words.
  static const stages = <String>['Sent', 'Assigned', 'On the way', 'With you', 'Done'];

  /// How many of [stages] are behind us. Drives the rail, so the shape of the
  /// screen answers "where are we up to" before any of it is read.
  int get stage {
    switch (status) {
      case 'submitted':
      case 'dispatching':
      case 'assigned':
      case 'unclaimed':
        return 1;
      case 'accepted':
        return 2;
      case 'en_route':
        return 3;
      case 'arrived':
      case 'in_progress':
        return 4;
      case 'completed':
        return 5;
      default:
        return 0;
    }
  }

  /// The wording the customer sees. `assigned` is internal: until a technician
  /// has accepted, the honest answer is that we are still looking.
  String get headline {
    switch (status) {
      case 'submitted':
        return 'Request received';
      case 'dispatching':
      case 'assigned':
        return 'Finding a technician';
      case 'accepted':
        return 'Technician assigned';
      case 'en_route':
        return 'On the way to you';
      case 'arrived':
        return 'Arrived';
      case 'in_progress':
        return 'Work in progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'unclaimed':
        return 'We are calling round';
      default:
        return statusDisplay;
    }
  }

  String get blurb {
    switch (status) {
      case 'submitted':
      case 'dispatching':
      case 'assigned':
        return 'We are offering your job to the technicians nearest to you.';
      case 'accepted':
        return 'Your technician has accepted and will set off shortly.';
      case 'en_route':
        return 'Your technician is on the way.';
      case 'arrived':
        return 'Your technician is with you.';
      case 'in_progress':
        return 'Work has started on your vehicle.';
      case 'completed':
        return 'All done. Thank you for calling ShirazTyres.';
      case 'cancelled':
        return 'This request was cancelled.';
      case 'unclaimed':
        return 'Nobody is free right now — the office is calling round for you.';
      default:
        return '';
    }
  }
}

class TimelineEntry {
  const TimelineEntry({required this.status, required this.label, required this.at});

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
        status: asString(json['status']),
        label: asString(json['label']),
        at: asDate(json['at']),
      );

  final String status;
  final String label;
  final DateTime? at;
}
