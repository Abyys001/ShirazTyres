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

/// The driver who put their registration aside to finish later, by id.
///
/// Registration is not a gate the app can afford to hold somebody behind. A new
/// starter is often signed in on the forecourt with the paperwork in a van, or
/// sent the app the night before with nothing to photograph yet — and a cold
/// start used to drop them back on the same form with no way past it, on an
/// account the office could already see.
///
/// So the form is a destination, not a toll. The account is registered at first
/// sign-in either way and reaches the panel's approval queue with whatever it
/// has; this only decides whether the app opens *on* the form.
class DeferredSetupController extends Notifier<int?> {
  /// Whether somebody has decided since launch.
  ///
  /// Reading the device is asynchronous, and a driver can tap *Finish this
  /// later* — or finish it — while that read is still in flight. Letting the
  /// read land unconditionally would overwrite the newer choice with the older
  /// one, which on a slow keystore is exactly the launch where it matters:
  /// tap "later", get sent back to the form anyway.
  bool _decided = false;

  @override
  int? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    final stored = await ref.read(settingsStoreProvider).readDeferredSetup();
    if (_decided || stored == state) return;
    state = stored;
  }

  Future<void> deferFor(int driverId) async {
    _decided = true;
    state = driverId;
    await ref.read(settingsStoreProvider).writeDeferredSetup(driverId);
  }

  /// On completion, and on sign-out — see [AuthController.signOut].
  Future<void> clear() async {
    _decided = true;
    if (state == null) return;
    state = null;
    await ref.read(settingsStoreProvider).writeDeferredSetup(null);
  }
}

final deferredSetupProvider =
    NotifierProvider<DeferredSetupController, int?>(DeferredSetupController.new);
