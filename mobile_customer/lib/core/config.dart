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

  /// Google sign-in (specification 4.1). Empty in development, where the API's
  /// mock verifier accepts a `mock:<email>` token instead.
  static const String googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static const Duration requestTimeout = Duration(seconds: 20);
}
