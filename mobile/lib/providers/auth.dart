import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_api.dart';
import '../core/api_exception.dart';
import '../models/driver.dart';
import '../models/otp_challenge.dart';
import 'api.dart';
import 'push.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({required this.status, this.driver, this.error});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.signedOut() : this(status: AuthStatus.signedOut);

  final AuthStatus status;
  final Driver? driver;

  /// Why there is no profile, when the session itself is still good. The home
  /// screen shows this with a retry rather than spinning on a null driver.
  final String? error;

  bool get isSignedIn => status == AuthStatus.signedIn;
  bool get isResolved => status != AuthStatus.unknown;

  /// Section 8.2: a driver exists long before they may take work.
  bool get needsOnboarding => driver != null && !driver!.onboardingComplete;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    ref.listen<int>(sessionRevokedProvider, (_, __) => _onAuthLost());
    unawaited(restore());
    return const AuthState.unknown();
  }

  AuthApi get _auth => ref.read(authApiProvider);

  /// Cold start. The work phone is signed in once and stays signed in, so a
  /// stored refresh token *is* a session until the API refuses it. A technician
  /// in an underground car park reopens on the cached profile; only an outright
  /// refusal — or an office revoking the account — sends them back to the phone
  /// screen.
  Future<void> restore() async {
    state = const AuthState.unknown();
    try {
      await _restore();
    } catch (error) {
      // Reading the keystore, or a cached profile written by an older build, can
      // both throw. Whatever happened, the app must not be left on the splash
      // screen: the phone screen is always a way back in.
      state = AuthState(status: AuthStatus.signedOut, error: '$error');
    }
  }

  Future<void> _restore() async {
    final store = ref.read(tokenStoreProvider);
    final refresh = await store.readRefresh();
    if (refresh == null || refresh.isEmpty) {
      state = const AuthState.signedOut();
      return;
    }

    Map<String, dynamic>? cached = await store.readProfile();
    if (cached != null) {
      try {
        state = AuthState(status: AuthStatus.signedIn, driver: Driver.fromJson(cached));
      } catch (_) {
        // A profile this build cannot read is worth no more than no profile.
        cached = null;
      }
    }

    try {
      final profile = await ref.read(driverApiProvider).meRaw();
      await store.saveProfile(profile);
      state = AuthState(status: AuthStatus.signedIn, driver: Driver.fromJson(profile));
      await _registerDevice();
    } on ApiException catch (error) {
      if (error.isUnauthorised) {
        // Refresh already had its chance inside the client; this one is dead.
        await store.clear();
        state = const AuthState.signedOut();
      } else if (cached == null) {
        state = AuthState(status: AuthStatus.signedIn, error: error.message);
      }
    } catch (error) {
      // Anything that is not the API refusing us — a profile this build cannot
      // parse, a platform channel that threw — used to escape here and leave the
      // app on the splash screen with no way off it. A cold start now always
      // ends somewhere the driver can act.
      if (cached == null) {
        state = AuthState(
          status: AuthStatus.signedIn,
          error: 'Could not load your profile. $error',
        );
      }
    }
  }

  Future<void> refreshDriver() async {
    if (!state.isSignedIn) return;
    try {
      state = AuthState(
        status: AuthStatus.signedIn,
        driver: await ref.read(driverApiProvider).me(),
      );
    } on ApiException {
      // Callers refresh the profile as a courtesy after a change they already
      // know the outcome of. A stale profile is not worth an error for.
    }
  }

  Future<OtpChallenge> requestOtp(String phone) => _auth.requestCode(phone);

  /// No name here: onboarding asks for it, and the profile screen changes it.
  Future<bool> verifyOtp(String phone, String code) async {
    final session = await _auth.verify(phone: phone, code: code);
    await ref.read(tokenStoreProvider).save(access: session.access, refresh: session.refresh);
    state = AuthState(status: AuthStatus.signedIn, driver: session.driver);
    await _registerDevice();
    return session.isNew;
  }

  Future<void> updateProfile({String? name, String? email, XFile? photo}) async {
    final driver = await ref.read(driverApiProvider).updateProfile(
          name: name,
          email: email,
          photo: photo,
        );
    state = AuthState(status: AuthStatus.signedIn, driver: driver);
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
      // A missing push registration must never block a shift starting.
    }
  }

  void _onAuthLost() {
    state = const AuthState.signedOut();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

final currentDriverProvider = Provider<Driver?>((ref) => ref.watch(authControllerProvider).driver);
