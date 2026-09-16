import 'dart:io';

import 'package:flutter/foundation.dart';

/// Build-time configuration.
///
/// `flutter run --dart-define=API_BASE_URL=https://api.shiraztyres.co.uk/api/v1`
class AppConfig {
  const AppConfig._();

  static const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static const String _wsBaseUrlOverride = String.fromEnvironment('WS_BASE_URL');

  /// Left unset, the app talks to a development API on this machine. The host
  /// address differs per platform: an Android emulator reaches it on 10.0.2.2,
  /// an iOS simulator and desktop on localhost. Getting this wrong is silent —
  /// the request simply times out — so it is resolved rather than guessed.
  static String get apiBaseUrl =>
      _apiBaseUrlOverride.isNotEmpty ? _apiBaseUrlOverride : 'http://$_devHost:8000/api/v1';

  static String get wsBaseUrl =>
      _wsBaseUrlOverride.isNotEmpty ? _wsBaseUrlOverride : 'ws://$_devHost:8000/ws';

  static String get _devHost => Platform.isAndroid ? '10.0.2.2' : 'localhost';

  static const String officePhone = String.fromEnvironment(
    'OFFICE_PHONE',
    defaultValue: '+441234567890',
  );

  /// The map behind the location picker (specification 10.1, and the same rule
  /// the panel follows): production points at a tile service we are entitled to,
  /// set here at build time. Left unset a debug build borrows OpenStreetMap so
  /// the picker is usable on a development machine, and a release build draws
  /// its own graticule instead of quietly taking tiles we have not paid for.
  static const String _mapTileUrlOverride = String.fromEnvironment('MAP_TILE_URL');

  static String get mapTileUrl {
    if (_mapTileUrlOverride.isNotEmpty) return _mapTileUrlOverride;
    return kDebugMode ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png' : '';
  }

  static const String mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  /// Where the picker opens when there is no fix and nothing saved yet.
  static const double mapFallbackLatitude = 51.5074;
  static const double mapFallbackLongitude = -0.1278;

  static const Duration requestTimeout = Duration(seconds: 20);

  /// Section 11.1: updates go on a distance filter, not a timer, so a parked van
  /// stops sending and the battery survives the shift.
  static const int locationFilterMetres = 75;
  static const Duration locationTimeCap = Duration(minutes: 2);

  /// Whether to show the development sign-in helpers: the seeded phone numbers,
  /// and the OTP the mock SMS provider hands back instead of texting it.
  ///
  /// Debug builds against a local API only. A release build, or a debug build
  /// pointed at a real API, never shows them — `--dart-define=DEV_SIGN_IN=false`
  /// turns them off for a demo.
  static bool get devSignInEnabled {
    const override = String.fromEnvironment('DEV_SIGN_IN');
    if (override.isNotEmpty) return override.toLowerCase() == 'true';
    return kDebugMode && apiBaseUrl.startsWith('http://');
  }
}

/// A sign-in account offered as a one-tap fill on the development sign-in panel.
///
/// These are read from `GET /auth/dev/accounts` rather than being compiled in.
/// The list used to live here as a `const`, which meant a driver created in the
/// panel never appeared on this screen, and the numbers drifted out of date
/// every time the seed changed. The endpoint answers from the database, is
/// served only by a DEBUG build over plain http, and returns names and numbers
/// — never a code or a token.
class DevAccount {
  const DevAccount(this.phone, this.name, this.note);

  factory DevAccount.fromJson(Map<String, dynamic> json) {
    final state = (json['state'] ?? '').toString();
    final online = json['is_online'] == true;
    return DevAccount(
      (json['phone'] ?? '').toString(),
      (json['name'] ?? '').toString(),
      online ? '$state \u00b7 online' : state,
    );
  }

  final String phone;
  final String name;
  final String note;
}
