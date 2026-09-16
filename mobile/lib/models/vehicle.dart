import 'json.dart';

/// A customer's car as the plate tool answers for it: what DVLA holds, plus the
/// manufacturer's tyre fitment. Everything a technician needs before they open
/// the van doors.
class Vehicle {
  const Vehicle({
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
    required this.tyreSizeFront,
    required this.tyreSizeRear,
    required this.tyreLoadIndex,
    required this.tyreSpeedRating,
    required this.tyrePressureFrontPsi,
    required this.tyrePressureRearPsi,
    required this.tyreSizeOptions,
    required this.tyreSource,
    required this.motStatus,
    required this.motExpiryDate,
    required this.taxStatus,
    required this.taxDueDate,
    required this.lookupError,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: asInt(json['id']),
        plate: asString(json['plate']),
        displayPlate: asString(json['display_plate']),
        description: asString(json['description']),
        make: asString(json['make']),
        model: asString(json['model']),
        colour: asString(json['colour']),
        year: json['year_of_manufacture'] == null ? null : asInt(json['year_of_manufacture']),
        fuelType: asString(json['fuel_type']),
        engineCapacity: json['engine_capacity'] == null ? null : asInt(json['engine_capacity']),
        tyreSizeFront: asString(json['tyre_size_front']),
        tyreSizeRear: asString(json['tyre_size_rear']),
        tyreLoadIndex: asString(json['tyre_load_index']),
        tyreSpeedRating: asString(json['tyre_speed_rating']),
        tyrePressureFrontPsi: json['tyre_pressure_front_psi'] == null
            ? null
            : asInt(json['tyre_pressure_front_psi']),
        tyrePressureRearPsi: json['tyre_pressure_rear_psi'] == null
            ? null
            : asInt(json['tyre_pressure_rear_psi']),
        tyreSizeOptions: asStringList(json['tyre_size_options']),
        tyreSource: asString(json['tyre_source']),
        motStatus: asString(json['mot_status']),
        motExpiryDate: asDate(json['mot_expiry_date']),
        taxStatus: asString(json['tax_status']),
        taxDueDate: asDate(json['tax_due_date']),
        lookupError: asString(json['lookup_error']),
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
  final String tyreSizeFront;
  final String tyreSizeRear;
  final String tyreLoadIndex;
  final String tyreSpeedRating;
  final int? tyrePressureFrontPsi;
  final int? tyrePressureRearPsi;
  final List<String> tyreSizeOptions;
  final String tyreSource;
  final String motStatus;
  final DateTime? motExpiryDate;
  final String taxStatus;
  final DateTime? taxDueDate;
  final String lookupError;

  String get label => displayPlate.isNotEmpty ? displayPlate : plate;

  String get title => description.isNotEmpty ? description : '$make $model'.trim();

  /// A size the fitter can load the van with — anything else needs confirming.
  bool get hasTyreSize => tyreSizeFront.isNotEmpty;

  /// Staggered fitments are the ones that get a van sent out with the wrong
  /// pair, so the front/rear split is worth calling out rather than collapsing.
  bool get hasStaggeredFitment =>
      tyreSizeRear.isNotEmpty && tyreSizeRear != tyreSizeFront;

  bool get tyreSizeConfirmedByHuman => tyreSource == 'staff' || tyreSource == 'driver';

  /// The size with its load and speed markings, which is what is actually
  /// stamped on the sidewall and what a wholesaler is asked for.
  String get fullTyreSpec => <String>[
        tyreSizeFront,
        tyreLoadIndex,
        tyreSpeedRating,
      ].where((part) => part.isNotEmpty).join(' ');
}
