import 'package:flutter/material.dart';
import 'app_storage.dart';

import 'geo.dart';

/// Device preferences that outlive a sign-out.
///
/// Theme is a property of the phone and the person holding it, not of the
/// account: signing out on a shared handset should not throw somebody back into
/// a dark screen they turned off. So it lives here rather than in [TokenStore],
/// which is cleared on sign-out.
class SettingsStore {
  const SettingsStore(this._storage);

  final AppStorage _storage;

  static const _themeKey = 'st_theme_mode';
  static const _pinKey = 'st_manual_pin';
  static const _deferredSetupKey = 'st_setup_deferred_for';

  /// Anything unreadable reads as "not chosen", which follows the system. The
  /// preference is never important enough to fail a launch over.
  Future<ThemeMode> readThemeMode() async {
    try {
      return _decode(await _storage.read(key: _themeKey));
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> writeThemeMode(ThemeMode mode) async {
    try {
      await _storage.write(key: _themeKey, value: mode.name);
    } catch (_) {
      // The choice still applies for this launch; the next write may stick.
    }
  }

  /// A hand-set position outlives the process for the same reason it exists at
  /// all: the handset it is standing in for is the one that cannot be relied
  /// on, so making the driver re-drop the pin after every restart would undo
  /// the point of having one.
  Future<LatLng?> readPin() async {
    try {
      return parseLatLng(await _storage.read(key: _pinKey) ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> writePin(LatLng? point) async {
    try {
      if (point == null) {
        await _storage.delete(key: _pinKey);
      } else {
        await _storage.write(key: _pinKey, value: '${point.latitude},${point.longitude}');
      }
    } catch (_) {
      // As above: this launch still has the pin it was given.
    }
  }

  /// The driver who chose to finish registering later, by id.
  ///
  /// An id rather than a flag, because a handset is not a person: a technician
  /// who signs out and hands the phone to the next starter must not have their
  /// "later" inherited by somebody who has registered nothing at all.
  Future<int?> readDeferredSetup() async {
    try {
      return int.tryParse(await _storage.read(key: _deferredSetupKey) ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDeferredSetup(int? driverId) async {
    try {
      if (driverId == null) {
        await _storage.delete(key: _deferredSetupKey);
      } else {
        await _storage.write(key: _deferredSetupKey, value: '$driverId');
      }
    } catch (_) {
      // Worst case the next launch offers to set up again, which is a nudge
      // rather than a wall — every screen the driver can reach is still there.
    }
  }

  static ThemeMode _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
