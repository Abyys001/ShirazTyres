import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../models/driver.dart';
import '../providers/api.dart';
import '../providers/auth.dart';

const _documentTypes = <String, String>{
  'insurance': 'Insurance certificate',
  'licence': 'Driving licence',
  'mot': 'MOT certificate',
};

/// Registration (specification 8.1): profile and photograph, the van, and the
/// documents an administrator has to see before any job is sent out.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _plate = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(currentDriverProvider)?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await ref.read(authControllerProvider.notifier).refreshDriver();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    await _run(() => ref.read(authControllerProvider.notifier).updateProfile(name: _name.text.trim()));
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1200);
    if (picked == null) return;
    await _run(
      () => ref.read(authControllerProvider.notifier).updateProfile(photo: File(picked.path)),
    );
  }

  Future<void> _addVan() async {
    final plate = _plate.text.trim();
    if (plate.isEmpty) return;
    await _run(() async {
      await ref.read(driverApiProvider).addVehicle(plate);
      _plate.clear();
    });
  }

  Future<void> _uploadDocument(String type) async {
    final expiry = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      initialDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'When does it expire?',
    );
    if (expiry == null || !mounted) return;

    final picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000);
    if (picked == null) return;

    await _run(
      () => ref.read(driverApiProvider).uploadDocument(
            documentType: type,
            expiryDate: expiry,
            file: File(picked.path),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(currentDriverProvider);
    if (driver == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Set up your account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('1. Your details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _saveProfile,
                  child: const Text('Save name'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _pickPhoto,
                  child: Text(driver.photo.isEmpty ? 'Take photo' : 'Retake photo'),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Your first name and photograph are shown to the customer so they know who is coming. '
              'Nothing else about you is.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

          const SizedBox(height: 24),
          Text('2. Your van', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (driver.vehicles.isEmpty) ...<Widget>[
            TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Registration', hintText: 'AB12 CDE'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _addVan,
              child: const Text('Add van'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Make, model and colour fill in from the registration.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ] else
            for (final van in driver.vehicles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(formatPlate(van.plate)),
                subtitle: Text(van.description),
                trailing: van.isPrimary ? const Text('primary') : null,
              ),

          const SizedBox(height: 24),
          Text('3. Your documents', style: Theme.of(context).textTheme.titleMedium),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'The office checks these before approving you, and again when they are close to expiring.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final entry in _documentTypes.entries)
            _DocumentRow(
              label: entry.value,
              document: driver.documents
                  .where((document) => document.documentType == entry.key)
                  .fold<DriverDocument?>(null, (previous, current) => current),
              busy: _busy,
              onUpload: () => _uploadDocument(entry.key),
            ),

          const SizedBox(height: 24),
          if (driver.missingDocuments.isNotEmpty)
            Text(
              'Still outstanding: ${driver.missingDocuments.join(', ')}.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (!driver.isApproved)
            const Text('Everything is in. The office will approve you shortly.')
          else
            const Text('You are approved and can go online.'),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.label,
    required this.document,
    required this.busy,
    required this.onUpload,
  });

  final String label;
  final DriverDocument? document;
  final bool busy;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final status = document == null
        ? 'not uploaded'
        : document!.isExpired
            ? 'expired ${formatDateTime(document!.expiryDate)}'
            : '${document!.status} · expires ${formatDateTime(document!.expiryDate)}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(status),
      trailing: OutlinedButton(
        onPressed: busy ? null : onUpload,
        child: Text(document == null ? 'Upload' : 'Replace'),
      ),
    );
  }
}
