import 'package:geolocator/geolocator.dart';

class LocationResult {
  const LocationResult({this.latitude, this.longitude, this.accuracyMetres, this.error});

  final double? latitude;
  final double? longitude;
  final int? accuracyMetres;
  final String? error;

  bool get isFixed => latitude != null && longitude != null;
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
