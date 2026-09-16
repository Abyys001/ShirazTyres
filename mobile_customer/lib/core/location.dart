import 'package:geolocator/geolocator.dart';

import 'geo.dart';

/// Where a fix came from, which is the only difference the API cares about
/// between a phone that knew and a person who pointed.
///
/// The map pin is not a fallback for a broken GPS — it is the answer for a
/// phone with location switched off, a signal that will not settle indoors, and
/// the driver who is parked round the corner from where the pin dropped.
enum FixSource {
  device,
  pin;

  /// What `location_source` on the job is called (specification 4.4).
  String get wireName => this == FixSource.pin ? 'pin' : 'device';
}

class LocationResult {
  const LocationResult({
    this.latitude,
    this.longitude,
    this.accuracyMetres,
    this.source = FixSource.device,
    this.error,
  });

  /// A point somebody chose on the map. It has no accuracy figure because it
  /// has no measurement behind it — saying "±5 m" about a pin would be a lie
  /// dispatch might act on.
  LocationResult.pinned(LatLng point)
      : latitude = point.latitude,
        longitude = point.longitude,
        accuracyMetres = null,
        source = FixSource.pin,
        error = null;

  final double? latitude;
  final double? longitude;
  final int? accuracyMetres;
  final FixSource source;
  final String? error;

  bool get isFixed => latitude != null && longitude != null;

  bool get isPinned => source == FixSource.pin;

  LatLng? get point => isFixed ? LatLng(latitude!, longitude!) : null;
}

/// Section 4.4 — the app uses the native device permission, which is what gives
/// the accuracy needed at the roadside. There is no postcode fallback by design.
Future<LocationResult> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return const LocationResult(
      error: 'Turn on location services so we can find you. A postcode is not precise enough.',
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    return const LocationResult(
      error: 'We need your location to send a technician to the right place.',
    );
  }

  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMetres: position.accuracy.round(),
    );
  } on Exception {
    return const LocationResult(error: 'Could not get a GPS fix. Move into the open and try again.');
  }
}
