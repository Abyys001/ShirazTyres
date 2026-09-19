import 'package:cross_file/cross_file.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_driver/api/driver_api.dart';
import 'package:shiraztyres_driver/core/api_exception.dart';
import 'package:shiraztyres_driver/models/driver.dart';
import 'package:shiraztyres_driver/models/vehicle.dart';
import 'package:shiraztyres_driver/providers/api.dart';
import 'package:shiraztyres_driver/providers/auth.dart';
import 'package:shiraztyres_driver/providers/location.dart';

/// The shift toggle used to be derived from the profile, and `setOnline`
/// refreshes the profile before it finishes — so going off shift left a
/// technician unable to go back on until the app was restarted.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{
        'st_access': 'a',
        'st_refresh': 'r',
      }));

  Future<ProviderContainer> signedIn(_StubDriverApi api) async {
    final container = ProviderContainer(
      overrides: <Override>[
        driverApiProvider.overrideWithValue(api),
        locationReporterProvider.overrideWith(_StubReporter.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).restore();
    return container;
  }

  test('the shift goes off and back on again', () async {
    final api = _StubDriverApi();
    final container = await signedIn(api);
    final shift = container.read(availabilityProvider.notifier);

    expect(await shift.setOnline(true), isNull);
    expect(container.read(availabilityProvider).valueOrNull, isTrue);

    expect(await shift.setOnline(false), isNull);
    expect(container.read(availabilityProvider).valueOrNull, isFalse);

    expect(await shift.setOnline(true), isNull);
    expect(container.read(availabilityProvider).valueOrNull, isTrue);

    // The profile refresh lands after the toggle has settled. It must agree
    // with the switch rather than overrule it.
    await Future<void>.delayed(Duration.zero);
    expect(container.read(availabilityProvider).valueOrNull, isTrue);
  });

  test('a refusal from the API leaves the switch where the server has it', () async {
    final api = _StubDriverApi()..refuse = true;
    final container = await signedIn(api);

    expect(await container.read(availabilityProvider.notifier).setOnline(true), isNotNull);
    expect(container.read(availabilityProvider).valueOrNull, isFalse);
  });
}

/// Tracks `is_online` the way the API does, so `me()` and `setOnline` agree.
class _StubDriverApi implements DriverApi {
  bool online = false;
  bool refuse = false;

  Map<String, dynamic> get _row => <String, dynamic>{
        'id': 1,
        'name': 'Sam',
        'verification_status': 'approved',
        'is_online': online,
      };

  @override
  Future<Driver> setOnline(bool value) async {
    if (refuse) {
      throw const ApiException('Your account is not approved for dispatch yet.', statusCode: 400);
    }
    online = value;
    return Driver.fromJson(_row);
  }

  @override
  Future<Map<String, dynamic>> meRaw() async => _row;

  @override
  Future<Driver> me() async => Driver.fromJson(_row);

  @override
  Future<Driver> updateProfile({String? name, String? email, XFile? photo}) async =>
      Driver.fromJson(_row);

  @override
  Future<DriverVehicle> addVehicle(String plate) async => throw UnimplementedError();

  @override
  Future<List<DriverVehicle>> myVehicles() async => <DriverVehicle>[];

  @override
  Future<DriverVehicle> refreshVehicle(int id) async => throw UnimplementedError();

  @override
  Future<void> removeVehicle(int id) async => throw UnimplementedError();

  @override
  Future<Vehicle> lookupPlate(String plate) async => throw UnimplementedError();

  @override
  Future<DriverDocument> uploadDocument({
    required String documentType,
    required DateTime expiryDate,
    required XFile file,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> sendLocations(List<Map<String, dynamic>> points) async {}
}

/// Location reporting is the platform's business, not this test's.
class _StubReporter extends LocationReporter {
  _StubReporter(super.ref);

  @override
  Future<String?> start() async => null;

  @override
  Future<void> stop() async {}
}
