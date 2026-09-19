import 'json.dart';

/// The technician (specification section 2). Never the customer.
class Driver {
  const Driver({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.photo,
    required this.verificationStatus,
    required this.statusDisplay,
    required this.verificationNote,
    required this.isOnline,
    required this.vehicles,
    required this.documents,
    required this.missingDocuments,
  });

  factory Driver.fromJson(Map<String, dynamic> json) => Driver(
        id: asInt(json['id']),
        name: asString(json['name']),
        phone: asString(json['phone']),
        email: asString(json['email']),
        photo: asString(json['photo']),
        verificationStatus: asString(json['verification_status']),
        statusDisplay: asString(json['status_display']),
        verificationNote: asString(json['verification_note']),
        isOnline: json['is_online'] == true,
        vehicles: (json['vehicles'] as List? ?? const [])
            .map((item) => DriverVehicle.fromJson(asMap(item)))
            .toList(),
        documents: (json['documents'] as List? ?? const [])
            .map((item) => DriverDocument.fromJson(asMap(item)))
            .toList(),
        missingDocuments: asStringList(json['missing_documents']),
      );

  final int id;
  final String name;
  final String phone;
  final String email;
  final String photo;
  final String verificationStatus;
  final String statusDisplay;
  final String verificationNote;
  final bool isOnline;
  final List<DriverVehicle> vehicles;
  final List<DriverDocument> documents;
  final List<String> missingDocuments;

  bool get isApproved => verificationStatus == 'approved';
  bool get isSuspended => verificationStatus == 'suspended';
  bool get isRejected => verificationStatus == 'rejected';

  /// Registered, but not yet let into the dispatch pool. The default standing of
  /// every driver who has just signed in for the first time — section 8.2.
  bool get isPending => verificationStatus == 'pending';

  /// Everything asked of the driver is done and the decision is the office's.
  ///
  /// The difference between this and [isPending] is the whole of what the shift
  /// screen has to say: one is a job for the technician, the other is a job for
  /// a manager, and telling somebody to "finish your paperwork" when there is
  /// none left to finish is how an approval gets waited on twice.
  bool get awaitingReview => isPending && onboardingComplete;

  /// Uploaded documents nobody has reviewed yet.
  int get documentsInReview =>
      documents.where((document) => document.status == 'pending').length;

  DriverVehicle? get van =>
      vehicles.isEmpty ? null : vehicles.firstWhere((v) => v.isPrimary, orElse: () => vehicles.first);

  /// What still stands between this driver and their first job (section 8).
  bool get onboardingComplete =>
      name.isNotEmpty && vehicles.isNotEmpty && missingDocuments.isEmpty;
}

class DriverVehicle {
  const DriverVehicle({
    required this.id,
    required this.plate,
    required this.displayPlate,
    required this.description,
    required this.make,
    required this.model,
    required this.colour,
    required this.year,
    required this.fuelType,
    required this.engineCapacity,
    required this.taxStatus,
    required this.taxDueDate,
    required this.taxDaysRemaining,
    required this.motStatus,
    required this.motExpiryDate,
    required this.motDaysRemaining,
    required this.checkedAt,
    required this.isPrimary,
  });

  factory DriverVehicle.fromJson(Map<String, dynamic> json) => DriverVehicle(
        id: asInt(json['id']),
        plate: asString(json['plate']),
        displayPlate: asString(json['display_plate']),
        description: asString(json['description']),
        make: asString(json['make']),
        model: asString(json['model']),
        colour: asString(json['colour']),
        year: json['year_of_manufacture'] == null ? null : asInt(json['year_of_manufacture']),
        fuelType: asString(json['fuel_type']),
        engineCapacity:
            json['engine_capacity'] == null ? null : asInt(json['engine_capacity']),
        taxStatus: asString(json['tax_status']),
        taxDueDate: asDate(json['tax_due_date']),
        taxDaysRemaining:
            json['tax_days_remaining'] == null ? null : asInt(json['tax_days_remaining']),
        motStatus: asString(json['mot_status']),
        motExpiryDate: asDate(json['mot_expiry_date']),
        motDaysRemaining:
            json['mot_days_remaining'] == null ? null : asInt(json['mot_days_remaining']),
        checkedAt: asDate(json['dvla_fetched_at']),
        isPrimary: json['is_primary'] == true,
      );

  final int id;
  final String plate;
  final String displayPlate;
  final String description;
  final String make;
  final String model;
  final String colour;
  final int? year;
  final String fuelType;
  final int? engineCapacity;
  final String taxStatus;
  final DateTime? taxDueDate;

  /// Negative once it has lapsed, which is the number that matters.
  final int? taxDaysRemaining;
  final String motStatus;
  final DateTime? motExpiryDate;
  final int? motDaysRemaining;
  final DateTime? checkedAt;
  final bool isPrimary;

  String get title => description.isNotEmpty ? description : displayPlate;

  /// Anything DVLA has told us that is about to stop this van being legal. The
  /// screen leads with these, because they are the only part a driver can act
  /// on before it costs them a shift.
  bool get needsAttention =>
      (motDaysRemaining != null && motDaysRemaining! <= 30) ||
      (taxDaysRemaining != null && taxDaysRemaining! <= 30);
}

class DriverDocument {
  const DriverDocument({
    required this.id,
    required this.documentType,
    required this.typeDisplay,
    required this.expiryDate,
    required this.status,
    required this.reviewNote,
    required this.isExpired,
    required this.daysToExpiry,
  });

  factory DriverDocument.fromJson(Map<String, dynamic> json) => DriverDocument(
        id: asInt(json['id']),
        documentType: asString(json['document_type']),
        typeDisplay: asString(json['type_display']),
        expiryDate: asDate(json['expiry_date']),
        status: asString(json['status']),
        reviewNote: asString(json['review_note']),
        isExpired: json['is_expired'] == true,
        daysToExpiry: asInt(json['days_to_expiry']),
      );

  final int id;
  final String documentType;
  final String typeDisplay;
  final DateTime? expiryDate;
  final String status;
  final String reviewNote;
  final bool isExpired;
  final int daysToExpiry;
}
