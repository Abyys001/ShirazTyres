import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/secure_storage.dart';
import '../core/settings_store.dart';

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => const SettingsStore(appStorage),
);

/// The light/dark choice, read back from the device on launch.
///
/// It starts on [ThemeMode.system] and corrects itself once storage answers —
/// a frame or two later at worst, and only ever on the first build, so nobody
/// sees the app flip after they have started using it. Writing is fire and
/// forget: the switch has already moved, and the disk catching up is not
/// something the interface should wait on.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final stored = await ref.read(settingsStoreProvider).readThemeMode();
    if (stored != state) state = stored;
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(settingsStoreProvider).writeThemeMode(mode);
  }

  /// The one-tap version used on screens with no room for three options: it
  /// moves to the opposite of what is currently on screen, resolving
  /// [ThemeMode.system] against the device first.
  Future<void> toggle(Brightness showing) =>
      set(showing == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
