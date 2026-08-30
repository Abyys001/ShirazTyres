import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api_exception.dart';
import '../core/config.dart';
import '../core/location.dart';
import 'api.dart';
import 'auth.dart';

/// Location reporting, and nothing else, for as long as the driver is online.
///
/// Section 11.1 is explicit that tracking runs only while toggled online, so the
/// subscription is started and cancelled by the availability controller and by
/// nothing else. Fixes that cannot be sent are buffered and flushed, because a
/// technician on a hard shoulder is exactly where the signal goes.
class LocationReporter {
  LocationReporter(this._ref);

  final Ref _ref;

  StreamSubscription<Position>? _subscription;
  Timer? _heartbeat;
  final List<Map<String, dynamic>> _buffer = <Map<String, dynamic>>[];
  Position? _latest;

  bool get isRunning => _subscription != null;

  Future<String?> start() async {
    if (_subscription != null) return null;
    final blocked = await ensureLocationPermission();
    if (blocked != null) return blocked;

    _subscription = trackWhileOnline().listen((position) {
      _latest = position;
      _buffer.add(_encode(position));
      unawaited(_flush());
    });

    // The time cap: a stationary van still checks in occasionally so the panel
    // can tell "not moving" from "phone died".
    _heartbeat = Timer.periodic(AppConfig.locationTimeCap, (_) {
      final position = _latest;
      if (position != null) {
        _buffer.add(_encode(position));
      }
      unawaited(_flush());
    });

    return null;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _buffer.clear();
    _latest = null;
  }

  Map<String, dynamic> _encode(Position position) => <String, dynamic>{
        'latitude': position.latitude.toStringAsFixed(6),
        'longitude': position.longitude.toStringAsFixed(6),
        'accuracy_m': position.accuracy.round(),
        'speed_kph': (position.speed * 3.6).round().clamp(0, 400),
        'heading_deg': position.heading.round().clamp(0, 359),
        'recorded_at': position.timestamp.toUtc().toIso8601String(),
      };

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    try {
      await _ref.read(driverApiProvider).sendLocations(batch);
      _buffer.removeRange(0, batch.length);
    } on ApiException {
      // Keep them; the next fix or heartbeat tries again. The buffer is bounded
      // so a long outage cannot grow without limit.
      if (_buffer.length > 200) {
        _buffer.removeRange(0, _buffer.length - 200);
      }
    }
  }
}

final locationReporterProvider = Provider<LocationReporter>((ref) {
  final reporter = LocationReporter(ref);
  ref.onDispose(reporter.stop);
  return reporter;
});

/// The online toggle, and the only thing that starts or stops tracking.
class AvailabilityController extends Notifier<AsyncValue<bool>> {
  @override
  AsyncValue<bool> build() {
    final driver = ref.watch(currentDriverProvider);
    return AsyncValue<bool>.data(driver?.isOnline ?? false);
  }

  Future<String?> setOnline(bool online) async {
    state = const AsyncValue<bool>.loading();
    try {
      if (online) {
        final blocked = await ref.read(locationReporterProvider).start();
        if (blocked != null) {
          state = AsyncValue<bool>.data(ref.read(currentDriverProvider)?.isOnline ?? false);
          return blocked;
        }
      }

      final driver = await ref.read(driverApiProvider).setOnline(online);
      if (!driver.isOnline) {
        await ref.read(locationReporterProvider).stop();
      }
      await ref.read(authControllerProvider.notifier).refreshDriver();
      state = AsyncValue<bool>.data(driver.isOnline);
      return null;
    } on ApiException catch (error) {
      await ref.read(locationReporterProvider).stop();
      state = AsyncValue<bool>.data(ref.read(currentDriverProvider)?.isOnline ?? false);
      return error.message;
    }
  }
}

final availabilityProvider =
    NotifierProvider<AvailabilityController, AsyncValue<bool>>(AvailabilityController.new);
