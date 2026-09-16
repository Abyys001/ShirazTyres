import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api_exception.dart';
import '../core/config.dart';
import '../core/geo.dart';
import '../core/location.dart';
import '../models/driver.dart';
import 'api.dart';
import 'auth.dart';
import 'settings.dart';

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

  bool get isRunning => _heartbeat != null;

  LatLng? get _pin => _ref.read(manualPositionProvider);

  Future<String?> start() async {
    if (isRunning) return null;

    if (_pin == null) {
      final blocked = await ensureLocationPermission();
      if (blocked != null) return blocked;
      _listen();
    }

    // The time cap: a stationary van still checks in occasionally so the panel
    // can tell "not moving" from "phone died".
    _heartbeat = Timer.periodic(AppConfig.locationTimeCap, (_) => _report());

    return null;
  }

  /// The server now believes the shift is running, so a position it would have
  /// rejected a moment ago is worth sending. A pinned driver has nothing else
  /// to wait for — without this the panel would not place the van until the
  /// first heartbeat, two minutes later.
  void reportNow() {
    if (isRunning) _report();
  }

  /// The pin moved, or was dropped, while the shift is running: the panel
  /// should not wait a whole heartbeat to find out the van is somewhere else.
  /// Going back to the handset re-subscribes, and only then if it is allowed —
  /// a refusal leaves the shift running on the last pin rather than ending it.
  Future<void> onPinChanged() async {
    if (!isRunning) return;
    if (_pin == null) {
      if (_subscription == null && await ensureLocationPermission() == null) {
        _listen();
      }
    } else {
      await _subscription?.cancel();
      _subscription = null;
      _latest = null;
    }
    _report();
  }

  void _listen() {
    _subscription = trackWhileOnline().listen((position) {
      _latest = position;
      _buffer.add(_encode(position));
      unawaited(_flush());
    });
  }

  void _report() {
    final pin = _pin;
    if (pin != null) {
      _buffer.add(_encodePin(pin));
    } else if (_latest != null) {
      _buffer.add(_encode(_latest!));
    }
    unawaited(_flush());
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

  /// A pin claims a position and nothing else. Accuracy, speed and heading are
  /// left off rather than invented, and the ping model already allows that.
  Map<String, dynamic> _encodePin(LatLng point) => <String, dynamic>{
        'latitude': point.latitude.toStringAsFixed(6),
        'longitude': point.longitude.toStringAsFixed(6),
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
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

/// The position a driver set by hand, for a handset that will not give a fix.
///
/// Section 11.1 still wants a position on every ping; where it comes from is
/// the driver's problem to solve, not a reason to keep them off shift. While
/// this is set it wins over the GPS stream, which is not even subscribed to.
class ManualPosition extends Notifier<LatLng?> {
  @override
  LatLng? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    final stored = await ref.read(settingsStoreProvider).readPin();
    if (stored != null && state == null) state = stored;
  }

  void set(LatLng? point) {
    if (state == point) return;
    state = point;
    unawaited(ref.read(settingsStoreProvider).writePin(point));
    unawaited(ref.read(locationReporterProvider).onPinChanged());
  }
}

final manualPositionProvider =
    NotifierProvider<ManualPosition, LatLng?>(ManualPosition.new);

/// The online toggle, and the only thing that starts or stops tracking.
///
/// The controller owns the switch position. It used to `watch` the profile, and
/// `setOnline` refreshes the profile before it finishes — so the refresh
/// invalidated the controller, the invalidation outlived the value the toggle
/// had just written, and the next read re-derived the switch from a profile
/// fetched before the change landed. A technician who went off shift could not
/// get back on until the app was restarted.
///
/// So the profile is listened to rather than watched: it seeds the switch and
/// may correct it from the server, but it never re-answers a question that is
/// still being asked.
class AvailabilityController extends Notifier<AsyncValue<bool>> {
  bool _busy = false;

  @override
  AsyncValue<bool> build() {
    ref.listen<Driver?>(currentDriverProvider, (_, driver) {
      if (_busy || driver == null) return;
      state = AsyncValue<bool>.data(driver.isOnline);
    });
    return AsyncValue<bool>.data(ref.read(currentDriverProvider)?.isOnline ?? false);
  }

  Future<String?> setOnline(bool online) async {
    _busy = true;
    // Keeps the last answer visible under the spinner, so the switch does not
    // flick to "off" for the second it takes to turn on.
    state = const AsyncValue<bool>.loading().copyWithPrevious(state);
    try {
      if (online) {
        // A permission dialog that never comes back would otherwise leave the
        // switch disabled for the rest of the session.
        final blocked = await ref.read(locationReporterProvider).start().timeout(
              const Duration(seconds: 20),
              onTimeout: () => 'Could not start location. Check the permission and try again.',
            );
        if (blocked != null) {
          return _settle(ref.read(currentDriverProvider)?.isOnline ?? false, blocked);
        }
      }

      final driver = await ref.read(driverApiProvider).setOnline(online);
      if (driver.isOnline) {
        ref.read(locationReporterProvider).reportNow();
      } else {
        await ref.read(locationReporterProvider).stop();
      }
      // Inside the busy window on purpose: the profile catches up, the listener
      // above ignores it, and the toggle's own answer is written last.
      await ref.read(authControllerProvider.notifier).refreshDriver();
      return _settle(driver.isOnline, null);
    } on ApiException catch (error) {
      // Only a failed start-up stops tracking. A failed stop leaves the shift
      // running, which is what the server still believes.
      if (online) {
        await ref.read(locationReporterProvider).stop();
      }
      return _settle(ref.read(currentDriverProvider)?.isOnline ?? false, error.message);
    }
  }

  String? _settle(bool online, String? problem) {
    state = AsyncValue<bool>.data(online);
    _busy = false;
    return problem;
  }
}

final availabilityProvider =
    NotifierProvider<AvailabilityController, AsyncValue<bool>>(AvailabilityController.new);
