/// Build-time configuration.
///
/// `flutter run --dart-define=API_BASE_URL=https://api.shiraztyres.co.uk/api/v1`
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // 10.0.2.2 is the host machine as seen from the Android emulator.
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:8000/ws',
  );

  static const String officePhone = String.fromEnvironment(
    'OFFICE_PHONE',
    defaultValue: '+441234567890',
  );

  static const Duration requestTimeout = Duration(seconds: 20);

  /// Section 11.1: updates go on a distance filter, not a timer, so a parked van
  /// stops sending and the battery survives the shift.
  static const int locationFilterMetres = 75;
  static const Duration locationTimeCap = Duration(minutes: 2);
}
