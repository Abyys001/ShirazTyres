import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/api_exception.dart';
import '../core/config.dart';
import '../providers/auth.dart';

/// Sign-in (specification 4.1): Google or phone OTP, both landing on the same
/// account and the same job history.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        final challenge = await ref.read(authControllerProvider.notifier).requestOtp(_phone.text.trim());
        if (mounted) {
          setState(() {
            _codeSent = true;
            _code.text = challenge.debugCode;
          });
        }
      });

  Future<void> _verify() => _run(
        () => ref.read(authControllerProvider.notifier).verifyOtp(_phone.text.trim(), _code.text.trim()),
      );

  Future<void> _google() => _run(() async {
        if (AppConfig.googleServerClientId.isEmpty) {
          setState(() => _error = 'Google sign-in is not configured in this build.');
          return;
        }
        final account = await GoogleSignIn(
          serverClientId: AppConfig.googleServerClientId,
          scopes: const <String>['email', 'profile'],
        ).signIn();
        if (account == null) return;
        final authentication = await account.authentication;
        final idToken = authentication.idToken;
        if (idToken == null) {
          setState(() => _error = 'Google did not return a usable sign-in.');
          return;
        }
        await ref.read(authControllerProvider.notifier).signInWithGoogle(idToken);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 40),
              Icon(Icons.tire_repair, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text('ShirazTyres', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text('Flat tyre in London? We come to you.'),
              const SizedBox(height: 28),

              OutlinedButton.icon(
                onPressed: _busy ? null : _google,
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 20),
              Row(
                children: const <Widget>[
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or use your phone'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  hintText: '07700 900123',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              if (_codeSent) ...<Widget>[
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Code we texted you'),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
                child: Text(_codeSent ? 'Sign in' : 'Text me a code'),
              ),
              if (_codeSent)
                TextButton(
                  onPressed: _busy ? null : _sendCode,
                  child: const Text('Send another code'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
