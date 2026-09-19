import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../providers/api.dart';
import '../providers/auth.dart';
import '../widgets/auth_kit.dart';
import '../widgets/dev_sign_in.dart';
import '../widgets/ui_kit.dart';

/// Step 1 of driver registration (specification 8.1): the work mobile number.
///
/// The technician build wears the dark treatment its launcher icon does, so the
/// two apps are never confused for one another on a phone that has both.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final challenge =
          await ref.read(authControllerProvider.notifier).requestOtp(_phone.text.trim());
      if (!mounted) return;
      context.push('/otp', extra: <String, dynamic>{
        'phone': _phone.text.trim(),
        'resendAfter': challenge.resendAfterSeconds,
        'debugCode': challenge.debugCode,
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.fieldError('phone') ?? error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: AuthBackdrop(
        child: Form(
          key: _formKey,
          child: AuthLayout(
            children: <Widget>[
              const AuthHero(
                title: 'ShirazTyres',
                kicker: 'Technician',
              ),
              const SizedBox(height: Space.xxxl),
              Text('Your work mobile', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _sending ? null : _submit(),
                style: palette.mono.copyWith(fontSize: 22, letterSpacing: 1.5, color: palette.ink),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                decoration: InputDecoration(
                  hintText: '07700 900123',
                  hintStyle: palette.mono.copyWith(
                    fontSize: 22,
                    letterSpacing: 1.5,
                    color: palette.inkSubtle,
                  ),
                  prefixIcon: const Icon(Icons.smartphone_outlined),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.lg,
                  ),
                ),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp('[^0-9]'), '');
                  return digits.length < 10 ? 'Enter a full UK mobile number.' : null;
                },
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: Space.lg),
                InlineNotice(_error!),
              ],
              const SizedBox(height: Space.lg),
              BusyButton(label: 'Send code', busy: _sending, onPressed: _submit),
              const SizedBox(height: Space.xxxl),
              // What the job is, in three pictures. The same code either
              // signs a technician in or starts their registration, which is
              // the only thing this screen would otherwise have to explain.
              const BeatStrip(
                beats: <(IconData, String)>[
                  (Icons.bolt, 'Go on shift'),
                  (Icons.navigation_outlined, 'Take a job'),
                  (Icons.payments_outlined, 'Get paid'),
                ],
              ),
              const SizedBox(height: Space.xxl),
              // Read from the API, so a driver created in the panel is on
              // this list the moment they exist.
              DevSignInPanel(
                accounts: ref.watch(devAccountsProvider).valueOrNull?.accounts ??
                    const <DevAccount>[],
                onUse: (phone) => setState(() => _phone.text = phone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
