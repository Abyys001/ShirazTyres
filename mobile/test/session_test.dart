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

/// The work phone signs in once and stays signed in. These pin the two halves
/// of that: an API we cannot reach must not end a session, and an API that
/// refuses us must.
void main() {
  Future<AuthState> restoreWith(ApiException failure, {Map<String, String>? stored}) async {
    FlutterSecureStorage.setMockInitialValues(
      stored ?? <String, String>{'st_access': 'a', 'st_refresh': 'r'},
    );
    final container = ProviderContainer(
      overrides: <Override>[driverApiProvider.overrideWithValue(_FailingDriverApi(failure))],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).restore();
    return container.read(authControllerProvider);
  }

  test('an underground car park does not sign a technician out', () async {
    final state = await restoreWith(
      const ApiException('Cannot reach ShirazTyres. Check your signal and try again.'),
    );
    expect(state.isSignedIn, isTrue);
  });

  test('a 500 leaves the session alone', () async {
    final state = await restoreWith(const ApiException('Server trouble', statusCode: 500));
    expect(state.isSignedIn, isTrue);
  });

  test('a refused session ends it, and takes the tokens with it', () async {
    final state = await restoreWith(const ApiException('Not authorised', statusCode: 401));
    expect(state.isSignedIn, isFalse);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'st_refresh'), isNull);
  });

  test('a cold start with no refresh token is signed out without asking', () async {
    final state = await restoreWith(
      const ApiException('never called'),
      stored: <String, String>{},
    );
    expect(state.isSignedIn, isFalse);
  });

  test('the cached profile is what an offline start opens on', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'st_access': 'a',
      'st_refresh': 'r',
      'st_profile': '{"id":1,"name":"Sam","verification_status":"approved"}',
    });
    final container = ProviderContainer(
      overrides: <Override>[
        driverApiProvider.overrideWithValue(
          _FailingDriverApi(const ApiException('Cannot reach ShirazTyres.')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();
    final state = container.read(authControllerProvider);
    expect(state.isSignedIn, isTrue);
    expect(state.driver?.name, 'Sam');
  });
}

/// Every call fails the same way, which is the only behaviour these tests care
/// about.
class _FailingDriverApi implements DriverApi {
  const _FailingDriverApi(this.failure);

  final ApiException failure;

  @override
  Future<Map<String, dynamic>> meRaw() async => throw failure;

  @override
  Future<Driver> me() async => throw failure;

  @override
  Future<Driver> setOnline(bool online) async => throw failure;

  @override
  Future<Driver> updateProfile({String? name, String? email, XFile? photo}) async => throw failure;

  @override
  Future<DriverVehicle> addVehicle(String plate) async => throw failure;

  @override
  Future<List<DriverVehicle>> myVehicles() async => throw failure;

  @override
  Future<DriverVehicle> refreshVehicle(int id) async => throw failure;

  @override
  Future<void> removeVehicle(int id) async => throw failure;

  @override
  Future<Vehicle> lookupPlate(String plate) async => throw failure;

  @override
  Future<DriverDocument> uploadDocument({
    required String documentType,
    required DateTime expiryDate,
    required XFile file,
  }) async =>
      throw failure;

  @override
  Future<void> sendLocations(List<Map<String, dynamic>> points) async => throw failure;
}
