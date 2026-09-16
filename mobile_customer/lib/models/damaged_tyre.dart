/// Which wheels are damaged, and how badly — the shape `Job.damaged_positions`
/// stores on the API. Lives with the models rather than beside the picker so
/// the API client can speak it without importing a widget.
/// Where a wheel sits on the car. The values match `Job.TyrePosition` on the API.
enum TyrePosition {
  frontLeft('front_left', 'Nearside front', 'Front left'),
  frontRight('front_right', 'Offside front', 'Front right'),
  rearLeft('rear_left', 'Nearside rear', 'Rear left'),
  rearRight('rear_right', 'Offside rear', 'Rear right'),
  spare('spare', 'Spare', 'Spare');

  const TyrePosition(this.value, this.label, this.plain);

  /// What the API calls it.
  final String value;

  /// What the trade calls it — nearside is the kerb side on a UK car.
  final String label;

  /// What a customer standing next to the car calls it. Both are shown: the
  /// technician needs the first, and nobody stranded on the A40 knows it.
  final String plain;

  static TyrePosition? fromValue(String value) {
    for (final position in TyrePosition.values) {
      if (position.value == value) return position;
    }
    return null;
  }
}

/// How bad it is. The values match `Job.TyreSeverity` on the API.
enum TyreSeverity {
  flat('flat', 'Completely flat'),
  deflating('deflating', 'Losing air'),
  damaged('damaged', 'Damaged but holding'),
  blowout('blowout', 'Blowout');

  const TyreSeverity(this.value, this.label);

  final String value;
  final String label;

  static TyreSeverity? fromValue(String value) {
    for (final severity in TyreSeverity.values) {
      if (severity.value == value) return severity;
    }
    return null;
  }
}

/// One damaged wheel, as the API stores it.
class DamagedTyre {
  const DamagedTyre({required this.position, this.severity, this.note = ''});

  final TyrePosition position;
  final TyreSeverity? severity;
  final String note;

  DamagedTyre copyWith({TyreSeverity? severity, String? note, bool clearSeverity = false}) =>
      DamagedTyre(
        position: position,
        severity: clearSeverity ? null : (severity ?? this.severity),
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'position': position.value,
        if (severity != null) 'severity': severity!.value,
        if (note.isNotEmpty) 'note': note,
      };

  static DamagedTyre? fromJson(Map<String, dynamic> json) {
    final position = TyrePosition.fromValue('${json['position'] ?? ''}');
    if (position == null) return null;
    return DamagedTyre(
      position: position,
      severity: TyreSeverity.fromValue('${json['severity'] ?? ''}'),
      note: '${json['note'] ?? ''}',
    );
  }
}

