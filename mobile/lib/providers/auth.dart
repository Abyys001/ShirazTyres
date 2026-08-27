import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_api.dart';
import '../core/api_exception.dart';
import '../models/driver.dart';
import '../models/otp_challenge.dart';
import 'api.dart';
import 'push.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({required this.status, this.driver});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.signedOut() : this(status: AuthStatus.signedOut);

  final AuthStatus status;
  final Driver? driver;

  bool get isSignedIn => status == AuthStatus.signedIn;
  bool get isResolved => status != AuthStatus.unknown;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    ref.listen<int>(sessionRevokedProvider, (_, __) => _onAuthLost());
    Future<void>.microtask(restore);
    return const AuthState.unknown();
  }

  AuthApi get _api => ref.read(authApiProvider);

  /// Cold start: a stored token is only trusted once the API confirms it.
  Future<void> restore() async {
    final access = await ref.read(tokenStoreProvider).readAccess();
    if (access == null || access.isEmpty) {
      state = const AuthState.signedOut();
      return;
    }
    try {
      state = AuthState(status: AuthStatus.signedIn, driver: await _api.me());
      await _registerDevice();
    } on ApiException {
      // Refresh already had its chance inside the client; anything left is dead.
      await ref.read(tokenStoreProvider).clear();
      state = const AuthState.signedOut();
    }
  }

  Future<OtpChallenge> requestOtp(String phone) => _api.requestOtp(phone);

  Future<bool> verifyOtp(String phone, String code, {String name = ''}) async {
    final session = await _api.verifyOtp(phone, code, name: name);
    await ref.read(tokenStoreProvider).save(
          access: session.access,
          refresh: session.refresh,
        );
    state = AuthState(status: AuthStatus.signedIn, driver: session.driver);
    await _registerDevice();
    return session.isNewDriver;
  }

  Future<void> updateProfile({String? name, String? email}) async {
    state = AuthState(
      status: AuthStatus.signedIn,
      driver: await _api.updateMe(name: name, email: email),
    );
  }

  Future<void> signOut() async {
    final token = await ref.read(pushServiceProvider).deviceToken();
    if (token != null) {
      try {
        await ref.read(deviceApiProvider).deregister(token);
      } on ApiException {
        // Signing out locally matters more than tidying the push table.
      }
    }
    await ref.read(tokenStoreProvider).clear();
    state = const AuthState.signedOut();
  }

  Future<void> _registerDevice() async {
    final token = await ref.read(pushServiceProvider).deviceToken();
    if (token == null) return;
    try {
      await ref.read(deviceApiProvider).register(token);
    } on ApiException {
      // A missing push registration must never block getting a tyre fitted.
    }
  }

  void _onAuthLost() {
    state = const AuthState.signedOut();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

final currentDriverProvider = Provider<Driver?>(
  (ref) => ref.watch(authControllerProvider).driver,
);
