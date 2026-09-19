import 'package:flutter/material.dart';
import 'app_storage.dart';

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
