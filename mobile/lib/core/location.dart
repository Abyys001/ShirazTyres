import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'config.dart';
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
    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMetres: position.accuracy.round(),
    );
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
///
/// Section 11.2: this has to survive the screen going off. A technician driving
/// to a call-out is not looking at the phone, and a plain foreground stream is
/// stopped by the operating system within minutes of the app going to the
/// background — the van would go dark on the office's map and drop out of
/// candidate ranking without anybody being told. On Android the fix is a
/// foreground service with a notification the driver can see; on iOS it is the
/// background-updates flag with the status indicator showing. Both make the
/// tracking visible to the person being tracked, which is the point.
Stream<Position> trackWhileOnline() {
  return Geolocator.getPositionStream(locationSettings: _onlineSettings());
}

LocationSettings _onlineSettings() {
  // The web build has neither a foreground service nor a background-updates
  // flag, and `AndroidSettings` would be handed to the browser implementation
  // that cannot read it — so the plain settings below are the web's answer.
  if (kIsWeb) {
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConfig.locationFilterMetres,
    );
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConfig.locationFilterMetres,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'ShirazTyres — on shift',
        notificationText: 'Sharing your location so the office can send you the nearest job.',
        notificationChannelName: 'On shift',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConfig.locationFilterMetres,
      activityType: ActivityType.automotiveNavigation,
      allowBackgroundLocationUpdates: true,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }
  return LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: AppConfig.locationFilterMetres,
  );
}
