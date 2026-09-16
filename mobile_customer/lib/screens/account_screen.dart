import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../providers/auth.dart';
import '../widgets/theme_switch.dart';
import '../widgets/ui_kit.dart';

/// Profile, and the "attach a phone number" step that joins a Google-first
/// account to the OTP route (specification 4.1).
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _phone = TextEditingController();
  final _code = TextEditingController();

  bool _codeSent = false;
  Timer? _ticker;
  int _resendIn = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final customer = ref.read(currentCustomerProvider);
    _name = TextEditingController(text: customer?.name ?? '');
    _email = TextEditingController(text: customer?.email ?? '');
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _name.dispose();
    _email.dispose();
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

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
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

  Future<void> _save() => _run(() async {
        await ref.read(authControllerProvider.notifier).updateProfile(
              name: _name.text.trim(),
              email: _email.text.trim(),
            );
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Saved.')));
        }
      });

  Future<void> _sendPhoneCode() => _run(() async {
        final challenge =
            await ref.read(authControllerProvider.notifier).requestOtp(_phone.text.trim());
        if (!mounted) return;
        setState(() {
          _codeSent = true;
          if (challenge.debugCode.isNotEmpty) _code.text = challenge.debugCode;
        });
        _startCountdown(challenge.resendAfterSeconds);
      });

  Future<void> _attachPhone() => _run(
        () => ref
            .read(authControllerProvider.notifier)
            .attachPhone(_phone.text.trim(), _code.text.trim()),
      );

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in with the same number or Google account.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) context.go('/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final customer = ref.watch(currentCustomerProvider);
    if (customer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Your account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxxl),
        children: <Widget>[
          SurfaceCard(
            wash: true,
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 28,
                  backgroundColor: palette.surfaceRaised,
                  backgroundImage:
                      customer.photoUrl.isEmpty ? null : NetworkImage(customer.photoUrl),
                  child: customer.photoUrl.isEmpty
                      ? Icon(Icons.person_outline, color: palette.inkSubtle)
                      : null,
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(customer.displayName, style: theme.textTheme.titleLarge),
                      if (customer.phone.isNotEmpty)
                        Text(customer.phone, style: palette.mono)
                      else if (customer.email.isNotEmpty)
                        Text(customer.email, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('Details'),
          // Sign-in no longer asks for a name, so this is where a new customer
          // meets the question — flagged until it is answered, because the
          // technician is looking for a person, not a phone number.
          SurfaceCard(
            accent: customer.name.isEmpty ? palette.gold : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (customer.name.isEmpty) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.waving_hand_outlined, size: 22, color: palette.gold),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          'What should we call you?',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                ],
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: Space.md),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: Space.lg),
                BusyButton(label: 'Save', busy: _busy, onPressed: _save),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('Phone number'),
          SurfaceCard(
            accent: customer.needsPhone ? palette.warning : palette.success,
            child: customer.needsPhone ? _attachPhoneForm(theme) : _verifiedPhone(customer.phone),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('Appearance'),
          const ThemeChoice(),

          if (_error != null) ...<Widget>[
            const SizedBox(height: Space.lg),
            InlineNotice(_error!),
          ],

          const SizedBox(height: Space.xxl),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.danger,
              side: BorderSide(color: palette.line),
            ),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Widget _verifiedPhone(String phone) => Row(
        children: <Widget>[
          Icon(Icons.verified_outlined, size: 18, color: context.palette.success),
          const SizedBox(width: Space.md),
          Expanded(child: Text(phone, style: context.palette.mono.copyWith(color: context.palette.ink))),
          Text('VERIFIED', style: context.palette.eyebrow.copyWith(color: context.palette.success)),
        ],
      );

  Widget _attachPhoneForm(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('So we can text you about your call-out.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              LengthLimitingTextInputFormatter(16),
            ],
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              hintText: '07700 900123',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_codeSent) ...<Widget>[
            const SizedBox(height: Space.md),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const <String>[AutofillHints.oneTimeCode],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Fonts.mono,
                fontSize: 22,
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
                color: context.palette.ink,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: const InputDecoration(hintText: '••••••', counterText: ''),
            ),
          ],
          const SizedBox(height: Space.lg),
          BusyButton(
            label: _codeSent ? 'Add this number' : 'Text me a code',
            busy: _busy,
            onPressed: _codeSent ? _attachPhone : _sendPhoneCode,
          ),
          if (_codeSent)
            TextButton(
              onPressed: _busy || _resendIn > 0 ? null : _sendPhoneCode,
              child: Text(_resendIn > 0 ? 'Send another in ${_resendIn}s' : 'Send another code'),
            ),
        ],
      );
}
