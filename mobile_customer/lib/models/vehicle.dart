import 'json.dart';

class Vehicle {
  const Vehicle({
    required this.id,
    required this.plate,
    required this.displayPlate,
    required this.description,
    required this.make,
    required this.model,
    required this.colour,
    required this.tyreSizeFront,
    required this.tyreSizeRear,
    required this.tyreSizeOptions,
    required this.tyreSource,
    required this.motExpiryDate,
    required this.taxStatus,
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
        tyreSizeFront: asString(json['tyre_size_front']),
        tyreSizeRear: asString(json['tyre_size_rear']),
        tyreSizeOptions: asStringList(json['tyre_size_options']),
        tyreSource: asString(json['tyre_source']),
        motExpiryDate: asDate(json['mot_expiry_date']),
        taxStatus: asString(json['tax_status']),
        lookupError: asString(json['lookup_error']),
      );

  final int id;
  final String plate;
  final String displayPlate;
  final String description;
  final String make;
  final String model;
  final String colour;
  final String tyreSizeFront;
  final String tyreSizeRear;
  final List<String> tyreSizeOptions;
  final String tyreSource;
  final DateTime? motExpiryDate;
  final String taxStatus;
  final String lookupError;

  String get label => displayPlate.isNotEmpty ? displayPlate : plate;

  String get title => description.isNotEmpty ? description : '$make $model'.trim();

  /// A size the fitter can load the van with — anything else needs confirming.
  bool get hasTyreSize => tyreSizeFront.isNotEmpty;

  bool get tyreSizeConfirmedByHuman => tyreSource == 'staff' || tyreSource == 'driver';
}
