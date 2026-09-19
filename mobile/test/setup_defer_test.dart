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
import 'package:shiraztyres_driver/providers/settings.dart';

/// Registration is a destination, not a toll. A technician whose documents are
/// in the van must be able to leave the form, and must not be dropped back on
/// it by the next cold start — their account is registered with the office from
/// the first sign-in either way.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{
        'st_access': 'a',
        'st_refresh': 'r',
      }));

  Future<ProviderContainer> signedIn(_StubDriverApi api) async {
    final container = ProviderContainer(
      overrides: <Override>[driverApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).restore();
    return container;
  }

  test('an incomplete registration still wants the form', () async {
    final container = await signedIn(_StubDriverApi());
    expect(container.read(authControllerProvider).needsOnboarding, isTrue);
    expect(container.read(deferredSetupProvider), isNull);
  });

  test('deferring is remembered for that driver, and survives a restart', () async {
    final container = await signedIn(_StubDriverApi());
    await container.read(deferredSetupProvider.notifier).deferFor(7);
    expect(container.read(deferredSetupProvider), 7);

    // A second container is the next cold start: it reads the choice back off
    // the device rather than inheriting it from the one that made it.
    final restarted = await signedIn(_StubDriverApi());
    expect(restarted.read(deferredSetupProvider), isNull, reason: 'before the device answers');
    await Future<void>.delayed(Duration.zero);
    expect(restarted.read(deferredSetupProvider), 7);
  });

  test('a handset does not pass one driver\'s "later" to the next', () async {
    final container = await signedIn(_StubDriverApi());
    await container.read(deferredSetupProvider.notifier).deferFor(7);

    await container.read(authControllerProvider.notifier).signOut();
    expect(container.read(deferredSetupProvider), isNull);
    expect(await container.read(settingsStoreProvider).readDeferredSetup(), isNull);
  });

  test('a choice made mid-launch is not overwritten by the device read', () async {
    final container = await signedIn(_StubDriverApi());
    await container.read(deferredSetupProvider.notifier).deferFor(7);

    // A fresh container whose restore is still in flight when the driver acts.
    final restarted = await signedIn(_StubDriverApi());
    restarted.read(deferredSetupProvider); // starts the read
    await restarted.read(deferredSetupProvider.notifier).clear();
    await Future<void>.delayed(Duration.zero);

    expect(restarted.read(deferredSetupProvider), isNull);
  });

  test('finishing the form clears it', () async {
    final container = await signedIn(_StubDriverApi());
    await container.read(deferredSetupProvider.notifier).deferFor(7);
    await container.read(deferredSetupProvider.notifier).clear();

    expect(container.read(deferredSetupProvider), isNull);
    expect(await container.read(settingsStoreProvider).readDeferredSetup(), isNull);
  });

  test('deferring never claims the account is unregistered', () async {
    // The record exists at the API from the first sign-in — the app has an id
    // for it — so "finish later" is about the form, never about registering.
    final container = await signedIn(_StubDriverApi());
    final driver = container.read(currentDriverProvider);
    expect(driver, isNotNull);
    expect(driver!.id, 7);
    expect(driver.isPending, isTrue);
  });
}

class _StubDriverApi implements DriverApi {
  Map<String, dynamic> get _row => <String, dynamic>{
        'id': 7,
        'name': '',
        'phone': '07700900401',
        'verification_status': 'pending',
        'is_online': false,
        'vehicles': <dynamic>[],
        'documents': <dynamic>[],
        'missing_documents': <dynamic>['insurance', 'licence', 'mot'],
      };

  @override
  Future<Map<String, dynamic>> meRaw() async => _row;

  @override
  Future<Driver> me() async => Driver.fromJson(_row);

  @override
  Future<Driver> setOnline(bool value) async =>
      throw const ApiException('Not approved.', statusCode: 400);

  @override
  Future<Driver> updateProfile({String? name, String? email, XFile? photo}) async =>
      Driver.fromJson(<String, dynamic>{..._row, if (name != null) 'name': name});

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
