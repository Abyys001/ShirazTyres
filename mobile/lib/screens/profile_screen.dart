import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../providers/auth.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final driver = ref.read(currentDriverProvider);
    _name = TextEditingController(text: driver?.name ?? '');
    _email = TextEditingController(text: driver?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            name: _name.text.trim(),
            email: _email.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(currentDriverProvider);
    if (driver == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Your account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 28,
              backgroundImage: driver.photo.isEmpty ? null : NetworkImage(driver.photo),
              child: driver.photo.isEmpty ? const Icon(Icons.person_outline) : null,
            ),
            title: Text(driver.phone),
            subtitle: Text(driver.statusDisplay),
          ),
          const SizedBox(height: 8),
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
          FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),

          const SizedBox(height: 24),
          Text('Your van', style: Theme.of(context).textTheme.titleSmall),
          if (driver.vehicles.isEmpty)
            const Text('No van registered.')
          else
            for (final van in driver.vehicles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(formatPlate(van.plate)),
                subtitle: Text(van.description),
              ),

          const SizedBox(height: 16),
          Text('Documents', style: Theme.of(context).textTheme.titleSmall),
          for (final document in driver.documents)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(document.typeDisplay),
              subtitle: Text(
                document.isExpired
                    ? 'Expired ${formatDateTime(document.expiryDate)}'
                    : '${document.status} · expires ${formatDateTime(document.expiryDate)}',
              ),
              trailing: document.isExpired
                  ? Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/onboarding'),
            child: const Text('Update documents'),
          ),

          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go('/phone');
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
