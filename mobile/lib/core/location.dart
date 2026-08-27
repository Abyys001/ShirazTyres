import 'package:geolocator/geolocator.dart';

class LocationResult {
  const LocationResult({this.latitude, this.longitude, this.error});

  final double? latitude;
  final double? longitude;
  final String? error;

  bool get isFixed => latitude != null && longitude != null;
}

/// Best-effort GPS. A refusal or a timeout is never fatal — the driver can
/// always type where they are instead.
Future<LocationResult> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return const LocationResult(error: 'Location services are switched off.');
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return const LocationResult(error: 'Location permission refused.');
  }

  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return LocationResult(latitude: position.latitude, longitude: position.longitude);
  } on Exception {
    return const LocationResult(error: 'Could not get a GPS fix.');
  }
}
