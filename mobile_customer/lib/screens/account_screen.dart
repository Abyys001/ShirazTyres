import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../providers/auth.dart';

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

  @override
  Widget build(BuildContext context) {
    final customer = ref.watch(currentCustomerProvider);
    if (customer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Your account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(
                      () => ref.read(authControllerProvider.notifier).updateProfile(
                            name: _name.text.trim(),
                            email: _email.text.trim(),
                          ),
                    ),
            child: const Text('Save'),
          ),

          const SizedBox(height: 28),
          Text('Phone number', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (!customer.needsPhone)
            Text('${customer.phone} — verified.')
          else ...<Widget>[
            const Text(
              'Add your mobile number so we can text you about your call-out, and so signing in by '
              'phone reaches this same account.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number'),
            ),
            if (_codeSent) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Code we texted you'),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        if (!_codeSent) {
                          final challenge = await ref
                              .read(authControllerProvider.notifier)
                              .requestOtp(_phone.text.trim());
                          if (mounted) {
                            setState(() {
                              _codeSent = true;
                              _code.text = challenge.debugCode;
                            });
                          }
                        } else {
                          await ref
                              .read(authControllerProvider.notifier)
                              .attachPhone(_phone.text.trim(), _code.text.trim());
                        }
                      }),
              child: Text(_codeSent ? 'Add this number' : 'Text me a code'),
            ),
          ],

          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],

          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go('/sign-in');
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
