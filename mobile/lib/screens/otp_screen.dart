import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../providers/auth.dart';
import '../widgets/auth_kit.dart';
import '../widgets/brand_logo.dart';
import '../widgets/dev_sign_in.dart';
import '../widgets/ui_kit.dart';

/// Step 1 of driver registration, continued: proving the number.
///
/// Nothing else is asked for here. The name belongs to onboarding, where it can
/// be corrected, and this screen is six digits and one button.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    required this.phone,
    this.resendAfterSeconds = 60,
    this.debugCode = '',
    super.key,
  });

  final String phone;
  final int resendAfterSeconds;

  /// Populated only when the backend runs with SMS_PROVIDER=mock.
  final String debugCode;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  Timer? _ticker;
  int _secondsLeft = 0;
  int _resendFrom = 0;
  String _debugCode = '';
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _debugCode = widget.debugCode;
    _code.text = widget.debugCode;
    _startCountdown(widget.resendAfterSeconds);
    WidgetsBinding.instance.addPostFrameCallback((_) => _codeFocus.requestFocus());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    setState(() {
      _secondsLeft = seconds;
      _resendFrom = seconds;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _resend() async {
    try {
      final challenge = await ref.read(authControllerProvider.notifier).requestOtp(widget.phone);
      if (!mounted) return;
      _startCountdown(challenge.resendAfterSeconds);
      setState(() {
        _error = null;
        if (challenge.debugCode.isNotEmpty) {
          _debugCode = challenge.debugCode;
          _code.text = challenge.debugCode;
        }
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the code we texted you.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final created = await ref.read(authControllerProvider.notifier).verifyOtp(widget.phone, code);
      if (!mounted) return;
      // The router sends an unapproved driver to onboarding on its own; this is
      // only here so a deep-linked push does not leave the stack on the code.
      context.go(created ? '/onboarding' : '/');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.fieldError('code') ?? error.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: AuthBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => context.pop(),
                  icon: Icon(Icons.arrow_back),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const BrandLogo(height: 44),
                      const SizedBox(height: Space.xl),
                      Text('Six digits', style: theme.textTheme.displaySmall),
                      const SizedBox(height: Space.xs),
                      Text(
                        widget.phone,
                        style: palette.mono.copyWith(fontSize: 18, color: palette.inkMuted),
                      ),
                      const SizedBox(height: Space.xxl),
                      CodeField(
                        controller: _code,
                        focusNode: _codeFocus,
                        enabled: !_verifying,
                        onCompleted: () {
                          if (!_verifying) _verify();
                        },
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: Space.lg),
                        InlineNotice(_error!),
                      ],
                      const SizedBox(height: Space.xl),
                      BusyButton(label: 'Continue', busy: _verifying, onPressed: _verify),
                      const SizedBox(height: Space.md),
                      Center(
                        child: ResendRing(
                          secondsLeft: _secondsLeft,
                          total: _resendFrom,
                          onResend: _resend,
                        ),
                      ),
                      const SizedBox(height: Space.xl),
                      // No account list here — the number is already chosen.
                      DevSignInPanel(debugCode: _debugCode),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
