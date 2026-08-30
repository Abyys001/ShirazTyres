import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../models/customer.dart';
import '../models/otp_challenge.dart';
import 'api.dart';
import 'push.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({required this.status, this.customer});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.signedOut() : this(status: AuthStatus.signedOut);

  final AuthStatus status;
  final Customer? customer;

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

  Future<void> restore() async {
    final access = await ref.read(tokenStoreProvider).readAccess();
    if (access == null || access.isEmpty) {
      state = const AuthState.signedOut();
      return;
    }
    try {
      state = AuthState(status: AuthStatus.signedIn, customer: await ref.read(authApiProvider).me());
      await _registerDevice();
    } on ApiException {
      await ref.read(tokenStoreProvider).clear();
      state = const AuthState.signedOut();
    }
  }

  Future<OtpChallenge> requestOtp(String phone) => ref.read(authApiProvider).requestCode(phone);

  Future<void> verifyOtp(String phone, String code) async {
    final session = await ref.read(authApiProvider).verifyOtp(phone: phone, code: code);
    await _adopt(session.access, session.refresh, session.customer);
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
    state = const AuthState.signedOut();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

final currentCustomerProvider =
    Provider<Customer?>((ref) => ref.watch(authControllerProvider).customer);
