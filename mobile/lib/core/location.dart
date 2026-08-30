import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'config.dart';

class LocationResult {
  const LocationResult({this.latitude, this.longitude, this.error});

  final double? latitude;
  final double? longitude;
  final String? error;

  bool get isFixed => latitude != null && longitude != null;
}

/// Best-effort single fix, used when a screen needs a position right now.
Future<LocationResult> currentLocation() async {
  final permitted = await ensureLocationPermission();
  if (permitted != null) return LocationResult(error: permitted);

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

/// Returns null when tracking may proceed, or the reason it may not.
Future<String?> ensureLocationPermission() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return 'Location services are switched off.';
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    return 'ShirazTyres needs your location while you are online, so we can send you the nearest job.';
  }
  return null;
}

/// The position stream used while the driver is online (specification 11.1).
///
/// A distance filter rather than a timer: a van parked at a job stops sending
/// almost entirely, which is the difference between a shift and a flat battery.
Stream<Position> trackWhileOnline() {
  return Geolocator.getPositionStream(
    locationSettings: LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConfig.locationFilterMetres,
    ),
  );
}
