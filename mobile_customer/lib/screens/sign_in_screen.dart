import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/api_exception.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../providers/api.dart';
import '../providers/auth.dart';
import '../widgets/auth_kit.dart';
import '../widgets/dev_sign_in.dart';
import '../widgets/ui_kit.dart';

/// Sign-in (specification 4.1): Google or phone OTP, both landing on the same
/// account and the same job history.
///
/// One screen, two steps, and as close to no reading as the flow allows. What
/// the service does is three pictures at the foot of the page rather than a
/// sentence at the top of it, and the name is not asked for here at all — it
/// belongs on the account screen, where it can be changed.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _Step { phone, code }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  _Step _step = _Step.phone;
  Timer? _ticker;
  int _resendIn = 0;
  int _resendFrom = 0;
  String _debugCode = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
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
      if (mounted) setState(() => _error = error.fieldError('phone') ?? error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    setState(() {
      _resendIn = seconds;
      _resendFrom = seconds;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_resendIn <= 1) {
        timer.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn -= 1);
      }
    });
  }

  Future<void> _sendCode() => _run(() async {
        final challenge =
            await ref.read(authControllerProvider.notifier).requestOtp(_phone.text.trim());
        if (!mounted) return;
        setState(() {
          _step = _Step.code;
          _debugCode = challenge.debugCode;
          if (challenge.debugCode.isNotEmpty) _code.text = challenge.debugCode;
        });
        _startCountdown(challenge.resendAfterSeconds);
        _codeFocus.requestFocus();
      });

  Future<void> _verify() => _run(() async {
        final created = await ref
            .read(authControllerProvider.notifier)
            .verifyOtp(_phone.text.trim(), _code.text.trim());
        if (created && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Welcome to ShirazTyres.')),
          );
        }
      });

  Future<void> _google() => _run(() async {
        if (AppConfig.googleServerClientId.isEmpty) {
          setState(() => _error = AppConfig.devSignInEnabled
              ? 'No Google client ID in this build — use the mock sign-in below, or a phone number.'
              : 'Google sign-in is not configured in this build.');
          return;
        }
        final account = await GoogleSignIn(
          serverClientId: AppConfig.googleServerClientId,
          scopes: const <String>['email', 'profile'],
        ).signIn();
        if (account == null) return;
        final idToken = (await account.authentication).idToken;
        if (idToken == null) {
          setState(() => _error = 'Google did not return a usable sign-in.');
          return;
        }
        await ref.read(authControllerProvider.notifier).signInWithGoogle(idToken);
      });

  void _editNumber() {
    _ticker?.cancel();
    setState(() {
      _step = _Step.phone;
      _resendIn = 0;
      _error = null;
      _code.clear();
      _debugCode = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: AuthBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxl, Space.xl, Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const AuthHero(title: 'ShirazTyres', kicker: 'We come to the tyre.'),
                const SizedBox(height: Space.xxxl),

                StepSwap(
                  stepKey: _step,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _step == _Step.phone ? _phoneStep(theme) : _codeStep(theme),
                  ),
                ),

                if (_error != null) ...<Widget>[
                  const SizedBox(height: Space.lg),
                  InlineNotice(_error!),
                ],

                const SizedBox(height: Space.xxxl),
                const BeatStrip(
                  beats: <(IconData, String)>[
                    (Icons.pin_outlined, 'Your reg'),
                    (Icons.local_shipping_outlined, 'We drive'),
                    (Icons.check_circle_outline, 'Fitted'),
                  ],
                ),

                const SizedBox(height: Space.xxl),
                // Read from the API, so a customer created anywhere is on this
                // list the moment they exist — and the mock Google token is
                // offered only when the API says that route is actually open.
                Builder(
                  builder: (context) {
                    final dev = ref.watch(devAccountsProvider).valueOrNull;
                    final googleMock = dev?.googleMock ?? '';
                    return DevSignInPanel(
                      accounts: dev?.accounts ?? const <DevAccount>[],
                      debugCode: _debugCode,
                      onUse: (phone) {
                        _phone.text = phone;
                        _editNumber();
                      },
                      extra: googleMock.isEmpty
                          ? null
                          : OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() => ref
                                      .read(authControllerProvider.notifier)
                                      .signInWithGoogle(googleMock)),
                              icon: const Icon(Icons.bolt_outlined, size: 18),
                              label: const Text('Mock Google sign-in'),
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneStep(ThemeData theme) => <Widget>[
        Text('Your mobile', style: theme.textTheme.headlineSmall),
        const SizedBox(height: Space.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const <String>[AutofillHints.telephoneNumber],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _sendCode(),
          style: context.palette.mono.copyWith(fontSize: 22, letterSpacing: 1.5, color: context.palette.ink),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            LengthLimitingTextInputFormatter(16),
          ],
          decoration: InputDecoration(
            hintText: '07700 900123',
            hintStyle: context.palette.mono.copyWith(fontSize: 22, letterSpacing: 1.5, color: context.palette.inkSubtle),
            prefixIcon: const Icon(Icons.smartphone_outlined),
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
          ),
        ),
        const SizedBox(height: Space.lg),
        BusyButton(label: 'Text me a code', busy: _busy, onPressed: _sendCode),
        const SizedBox(height: Space.xl),
        Row(
          children: <Widget>[
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Text('or', style: theme.textTheme.bodyMedium),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: Space.xl),
        OutlinedButton.icon(
          onPressed: _busy ? null : _google,
          icon: const Icon(Icons.account_circle_outlined, size: 22),
          label: const Text('Continue with Google'),
        ),
      ];

  List<Widget> _codeStep(ThemeData theme) => <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _phone.text.trim(),
                style: context.palette.mono.copyWith(fontSize: 20, color: context.palette.ink),
              ),
            ),
            TextButton(onPressed: _busy ? null : _editNumber, child: const Text('Change')),
          ],
        ),
        const SizedBox(height: Space.lg),
        CodeField(
          controller: _code,
          focusNode: _codeFocus,
          enabled: !_busy,
          onCompleted: () {
            if (!_busy) _verify();
          },
        ),
        const SizedBox(height: Space.lg),
        BusyButton(label: 'Sign in', busy: _busy, onPressed: _verify),
        const SizedBox(height: Space.md),
        Center(
          child: ResendRing(
            secondsLeft: _resendIn,
            total: _resendFrom,
            onResend: _busy ? null : _sendCode,
          ),
        ),
      ];
}
