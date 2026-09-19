import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_driver/api/driver_api.dart';
import 'package:shiraztyres_driver/api/job_api.dart';
import 'package:shiraztyres_driver/core/api_exception.dart';
import 'package:shiraztyres_driver/models/driver.dart';
import 'package:shiraztyres_driver/models/invoice.dart';
import 'package:shiraztyres_driver/models/job.dart';
import 'package:shiraztyres_driver/models/offer.dart';
import 'package:shiraztyres_driver/models/paginated.dart';
import 'package:shiraztyres_driver/models/vehicle.dart';
import 'package:shiraztyres_driver/providers/api.dart';
import 'package:shiraztyres_driver/providers/auth.dart';
import 'package:shiraztyres_driver/providers/jobs.dart';

/// A technician who has signed in but has not been approved yet is refused by
/// every dispatch endpoint. The shift screen used to ask anyway and render the
/// 403 as "Could not load offers" — a fault, with a Try again button that could
/// never work, in place of the sentence explaining the wait.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{
        'st_access': 'a',
        'st_refresh': 'r',
      }));

  Future<ProviderContainer> signedIn(_StubDriverApi driverApi, _StubJobApi jobApi) async {
    final container = ProviderContainer(
      overrides: <Override>[
        driverApiProvider.overrideWithValue(driverApi),
        jobApiProvider.overrideWithValue(jobApi),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).restore();
    return container;
  }

  test('a pending driver asks dispatch for nothing at all', () async {
    final jobApi = _StubJobApi();
    final container = await signedIn(_StubDriverApi(), jobApi);

    expect(container.read(canTakeWorkProvider), isFalse);
    expect(await container.read(offersProvider.future), isEmpty);
    expect(await container.read(availableJobsProvider.future), isEmpty);
    expect(await container.read(currentJobProvider.future), isNull);
    expect(await container.read(jobHistoryProvider.future), isEmpty);

    // Not one refusal, so nothing on the shift screen can read as a failure.
    expect(jobApi.calls, isEmpty);
  });

  test('a pull-to-refresh while pending still asks for nothing', () async {
    final jobApi = _StubJobApi();
    final container = await signedIn(_StubDriverApi(), jobApi);

    await container.read(offersProvider.future);
    await container.read(offersProvider.notifier).refresh();
    await container.read(availableJobsProvider.notifier).refresh();

    expect(jobApi.calls, isEmpty);
    expect(container.read(offersProvider).hasError, isFalse);
  });

  test('approval opens the lists without the app being reopened', () async {
    final driverApi = _StubDriverApi();
    final jobApi = _StubJobApi();
    final container = await signedIn(driverApi, jobApi);

    await container.read(offersProvider.future);
    expect(jobApi.calls, isEmpty);

    // What the office does, arriving on the socket or on a "Check again".
    driverApi.status = 'approved';
    await container.read(authControllerProvider.notifier).refreshDriver();
    expect(container.read(canTakeWorkProvider), isTrue);

    expect(await container.read(offersProvider.future), isEmpty);
    expect(jobApi.calls, contains('offers'));
  });

  test('the model keeps "your move" apart from "the office\'s move"', () {
    Driver build(Map<String, dynamic> extra) => Driver.fromJson(<String, dynamic>{
          'id': 1,
          'name': 'Sam',
          'verification_status': 'pending',
          'vehicles': <dynamic>[<String, dynamic>{'id': 1, 'plate': 'AB12CDE'}],
          'documents': <dynamic>[],
          'missing_documents': <dynamic>[],
          ...extra,
        });

    expect(build(<String, dynamic>{}).awaitingReview, isTrue);
    expect(build(<String, dynamic>{'missing_documents': <dynamic>['insurance']}).awaitingReview, isFalse);
    expect(build(<String, dynamic>{'name': ''}).awaitingReview, isFalse);
    expect(build(<String, dynamic>{'verification_status': 'approved'}).awaitingReview, isFalse);
    expect(build(<String, dynamic>{'verification_status': 'rejected'}).isRejected, isTrue);
  });
}

class _StubDriverApi implements DriverApi {
  String status = 'pending';

  Map<String, dynamic> get _row => <String, dynamic>{
        'id': 1,
        'name': 'Sam',
        'phone': '07700900305',
        'verification_status': status,
        'is_online': false,
        'vehicles': <dynamic>[],
        'documents': <dynamic>[],
        'missing_documents': <dynamic>[],
      };

  @override
  Future<Map<String, dynamic>> meRaw() async => _row;

  @override
  Future<Driver> me() async => Driver.fromJson(_row);

  @override
  Future<Driver> setOnline(bool value) async =>
      throw const ApiException('Your account is not approved for dispatch yet.', statusCode: 400);

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

/// Records every call, because the point of the change is that they stop being
/// made — a stub that answered happily would prove nothing.
class _StubJobApi implements JobApi {
  final List<String> calls = <String>[];

  @override
  Future<List<Offer>> offers() async {
    calls.add('offers');
    return <Offer>[];
  }

  @override
  Future<List<Job>> available() async {
    calls.add('available');
    return <Job>[];
  }

  @override
  Future<Paginated<Job>> jobs({String? status}) async {
    calls.add('jobs');
    return const Paginated<Job>(count: 0, results: <Job>[], next: '');
  }

  @override
  Future<List<ServiceItem>> priceList() async {
    calls.add('price-list');
    return <ServiceItem>[];
  }

  @override
  Future<Job> job(int id) async => throw UnimplementedError();

  @override
  Future<Job> claim(int id) async => throw UnimplementedError();

  @override
  Future<Job> accept(int id) async => throw UnimplementedError();

  @override
  Future<void> reject(int id, {String reason = ''}) async => throw UnimplementedError();

  @override
  Future<Job> setStatus(int id, String status, {String note = ''}) async =>
      throw UnimplementedError();

  @override
  Future<Job> correctTyre(int id, String tyreSize, {String note = ''}) async =>
      throw UnimplementedError();

  @override
  Future<Invoice> addLine(
    int jobId, {
    int? serviceItemId,
    String description = '',
    String? unitPrice,
    String quantity = '1',
    String kind = 'part',
  }) async =>
      throw UnimplementedError();

  @override
  Future<Invoice> removeLine(int jobId, int lineId) async => throw UnimplementedError();

  @override
  Future<Job> complete(int jobId, {String paymentMethod = '', String reference = ''}) async =>
      throw UnimplementedError();
}
