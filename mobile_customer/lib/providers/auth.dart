import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../models/customer.dart';
import '../models/otp_challenge.dart';
import 'api.dart';
import 'push.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({required this.status, this.customer, this.error});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.signedOut() : this(status: AuthStatus.signedOut);

  final AuthStatus status;
  final Customer? customer;

  /// Why there is no profile, when the session itself is still good.
  final String? error;

  bool get isSignedIn => status == AuthStatus.signedIn;
  bool get isResolved => status != AuthStatus.unknown;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    ref.listen<int>(sessionRevokedProvider, (_, __) => _onAuthLost());
    unawaited(restore());
    return const AuthState.unknown();
  }

  /// Cold start. The app is installed on one phone and signing in once is meant
  /// to be enough, so a stored refresh token *is* a signed-in session until the
  /// API refuses it. Anything short of a refusal — aeroplane mode, a captive
  /// portal, a flat 500 — reopens on the cached profile and re-confirms itself
  /// on the first call that gets through.
  Future<void> restore() async {
    state = const AuthState.unknown();
    try {
      await _restore();
    } catch (error) {
      // Reading the keystore, or a cached profile written by an older build, can
      // both throw. Whatever happened, the app must not be left on the splash
      // screen: the sign-in screen is always a way back in.
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
        state = AuthState(status: AuthStatus.signedIn, customer: Customer.fromJson(cached));
      } catch (_) {
        // A profile this build cannot read is worth no more than no profile.
        cached = null;
      }
    }

    try {
      final profile = await ref.read(authApiProvider).meRaw();
      await store.saveProfile(profile);
      state = AuthState(status: AuthStatus.signedIn, customer: Customer.fromJson(profile));
      await _registerDevice();
    } on ApiException catch (error) {
      if (error.isUnauthorised) {
        // The client already tried to refresh and was told no. This one is over.
        await store.clear();
        state = const AuthState.signedOut();
      } else if (cached == null) {
        state = AuthState(status: AuthStatus.signedIn, error: error.message);
      }
    } catch (error) {
      if (cached == null) {
        state = AuthState(
          status: AuthStatus.signedIn,
          error: 'Could not load your account. $error',
        );
      }
    }
  }

  Future<OtpChallenge> requestOtp(String phone) => ref.read(authApiProvider).requestCode(phone);

  /// Returns true when this code created the account, so the caller can welcome
  /// a new customer rather than a returning one. No name is collected here: it
  /// is asked for on the account screen, where it can also be changed.
  Future<bool> verifyOtp(String phone, String code) async {
    final session = await ref.read(authApiProvider).verifyOtp(phone: phone, code: code);
    await _adopt(session.access, session.refresh, session.customer);
    return session.isNew;
  }

  /// Section 4.1 — the same account whichever route the customer took.
  Future<void> signInWithGoogle(String idToken) async {
    final session = await ref.read(authApiProvider).google(idToken);
    await _adopt(session.access, session.refresh, session.customer);
  }

  Future<void> attachPhone(String phone, String code) async {
    final customer = await ref.read(authApiProvider).attachPhone(phone: phone, code: code);
    state = AuthState(status: AuthStatus.signedIn, customer: customer);
  }

  Future<void> updateProfile({String? name, String? email}) async {
    final customer = await ref.read(authApiProvider).updateMe(name: name, email: email);
    state = AuthState(status: AuthStatus.signedIn, customer: customer);
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
    await ref.read(jobCacheProvider).clear();
    state = const AuthState.signedOut();
  }

  Future<void> _adopt(String access, String refresh, Customer customer) async {
    await ref.read(tokenStoreProvider).save(access: access, refresh: refresh);
    state = AuthState(status: AuthStatus.signedIn, customer: customer);
    await _registerDevice();
  }

  Future<void> _registerDevice() async {
    final token = await ref.read(pushServiceProvider).deviceToken();
    if (token == null) return;
    try {
      await ref.read(deviceApiProvider).register(token);
    } on ApiException {
      // A missing push registration must never block a call-out.
    }
  }

  void _onAuthLost() {
    // The tokens are already gone; the cached call-out must not outlive them on
    // a handset that gets signed into a second account.
    unawaited(ref.read(jobCacheProvider).clear());
    state = const AuthState.signedOut();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

final currentCustomerProvider =
    Provider<Customer?>((ref) => ref.watch(authControllerProvider).customer);
