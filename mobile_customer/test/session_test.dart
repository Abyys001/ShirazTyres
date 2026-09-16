import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_customer/api/auth_api.dart';
import 'package:shiraztyres_customer/core/api_exception.dart';
import 'package:shiraztyres_customer/models/customer.dart';
import 'package:shiraztyres_customer/models/otp_challenge.dart';
import 'package:shiraztyres_customer/providers/api.dart';
import 'package:shiraztyres_customer/providers/auth.dart';

/// Signing in once is meant to last as long as the app is installed. These pin
/// the two halves of that: an API we cannot reach must not end a session, and an
/// API that refuses us must.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  Future<AuthState> restoreWith(ApiException failure, {Map<String, String>? stored}) async {
    FlutterSecureStorage.setMockInitialValues(
      stored ?? <String, String>{'st_access': 'a', 'st_refresh': 'r'},
    );
    final container = ProviderContainer(
      overrides: <Override>[authApiProvider.overrideWithValue(_FailingAuthApi(failure))],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).restore();
    return container.read(authControllerProvider);
  }

  test('an unreachable API leaves the session alone', () async {
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
      'st_profile': '{"id":7,"name":"Ada","phone":"07700900001"}',
    });
    final container = ProviderContainer(
      overrides: <Override>[
        authApiProvider.overrideWithValue(
          _FailingAuthApi(const ApiException('Cannot reach ShirazTyres.')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();
    final state = container.read(authControllerProvider);
    expect(state.isSignedIn, isTrue);
    expect(state.customer?.name, 'Ada');
  });
}

/// Every call fails the same way, which is the only behaviour these tests care
/// about.
class _FailingAuthApi implements AuthApi {
  const _FailingAuthApi(this.failure);

  final ApiException failure;

  @override
  Future<Map<String, dynamic>> meRaw() async => throw failure;

  @override
  Future<Customer> me() async => throw failure;

  @override
  Future<OtpChallenge> requestCode(String phone) async => throw failure;

  @override
  Future<CustomerSession> verifyOtp({required String phone, required String code}) async =>
      throw failure;

  @override
  Future<CustomerSession> google(String idToken) async => throw failure;

  @override
  Future<Customer> attachPhone({required String phone, required String code}) async =>
      throw failure;

  @override
  Future<Customer> updateMe({String? name, String? email}) async => throw failure;
}
