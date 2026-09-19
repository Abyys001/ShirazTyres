import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/driver.dart';
import '../providers/api.dart';
import '../providers/auth.dart';
import '../widgets/ui_kit.dart';

const _documentTypes = <String, String>{
  'insurance': 'Insurance certificate',
  'licence': 'Driving licence',
  'mot': 'MOT certificate',
};

/// Registration (specification 8.1): profile and photograph, the van, and the
/// documents an administrator has to see before any job is sent out.
///
/// The three steps are shown as a progress bar, because a driver who cannot see
/// what is left assumes they are finished and waits on an approval that is never
/// coming.
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() =>
      _run(() => ref.read(authControllerProvider.notifier).updateProfile(name: _name.text.trim()));

  /// Leave the form with the account registered as far as it got.
  ///
  /// The driver record was created at the first sign-in and is already in the
  /// panel's approval queue — this does not skip *registering*, only the rest
  /// of the form, which the account screen goes on asking for. What it must not
  /// do is throw away what is on screen: a name typed but never saved would
  /// leave the office an unnamed applicant and a phone number, which is the one
  /// thing they cannot chase anybody with. So it is sent first.
  Future<void> _leave() async {
    Buzz.tap();
    final driver = ref.read(currentDriverProvider);
    final typed = _name.text.trim();

    if (typed.isNotEmpty && typed != driver?.name) {
      await _run(
        () => ref.read(authControllerProvider.notifier).updateProfile(name: typed),
      );
    }
    if (!mounted) return;
    // Pushed from the account screen, or landed on directly from the very first
    // sign-in. Either way there has to be a way out that does not depend on
    // which.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1200);
    if (picked == null) return;
    await _run(
      () => ref.read(authControllerProvider.notifier).updateProfile(photo: picked),
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
            file: picked,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final driver = ref.watch(currentDriverProvider);
    if (driver == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final done = <bool>[
      driver.name.isNotEmpty,
      driver.vehicles.isNotEmpty,
      driver.missingDocuments.isEmpty,
    ];
    final completed = done.where((step) => step).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Set up your account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxxl),
        children: <Widget>[
          _Progress(completed: completed, total: done.length),
          const SizedBox(height: Space.xl),

          const SectionHeader('Your details', step: 1),
          SurfaceCard(
            accent: done[0] ? palette.success : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: palette.surfaceRaised,
                      backgroundImage: driver.photo.isEmpty ? null : NetworkImage(driver.photo),
                      child: driver.photo.isEmpty
                          ? Icon(Icons.person_outline, color: palette.inkSubtle)
                          : null,
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pickPhoto,
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text(driver.photo.isEmpty ? 'Take photo' : 'Retake photo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: Space.md),
                BusyButton(
                  label: 'Save name',
                  outlined: true,
                  busy: _busy,
                  onPressed: _saveProfile,
                ),
                const SizedBox(height: Space.md),
                Text(
                  'The customer sees your first name and photo. Nothing else.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('Your van', step: 2),
          SurfaceCard(
            accent: done[1] ? palette.success : null,
            child: driver.vehicles.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextField(
                        controller: _plate,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Registration',
                          hintText: 'AB12 CDE',
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      BusyButton(
                        label: 'Add van',
                        outlined: true,
                        busy: _busy,
                        onPressed: _addVan,
                      ),
                      const SizedBox(height: Space.md),
                      Text(
                        'Make, model and colour fill themselves in.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  )
                : Column(
                    children: <Widget>[
                      for (final van in driver.vehicles)
                        DetailRow(
                          van.isPrimary ? 'Primary van' : 'Van',
                          child: Row(
                            children: <Widget>[
                              PlateBadge(formatPlate(van.plate), dense: true),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Text(
                                  van.description,
                                  style: theme.textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('Your documents', step: 3),
          SurfaceCard(
            accent: done[2] ? palette.success : null,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
            child: Column(
              children: <Widget>[
                for (final entry in _documentTypes.entries)
                  _DocumentRow(
                    label: entry.value,
                    document: driver.documents
                        .where((document) => document.documentType == entry.key)
                        .fold<DriverDocument?>(null, (previous, current) => current),
                    busy: _busy,
                    onUpload: () => _uploadDocument(entry.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Checked before approval, and again near expiry.',
            style: theme.textTheme.bodySmall,
          ),

          const SizedBox(height: Space.xl),
          if (driver.missingDocuments.isNotEmpty)
            InlineNotice.warning('Still outstanding: ${driver.missingDocuments.join(', ')}.')
          else if (!driver.isApproved)
            const InlineNotice.info(
              'All in. Your account is now with the office for approval — you will '
              'be able to accept shifts as soon as they approve it.',
            )
          else
            InlineNotice(
              'Approved — you can go on shift.',
              tone: palette.success,
              icon: Icons.check_circle_outline,
            ),

          // A cold start with paperwork outstanding is *redirected* here, so
          // there is no back button to leave by. Somebody who finishes the last
          // step then sits on a completed form with nowhere to go, and never
          // sees the screen that explains what they are now waiting for — and
          // somebody whose documents are in the van has no way past it at all.
          const SizedBox(height: Space.lg),
          if (driver.onboardingComplete)
            FilledButton.icon(
              onPressed: _busy ? null : _leave,
              icon: const Icon(Icons.check, size: 19),
              label: const Text('Done'),
            )
          else ...<Widget>[
            OutlinedButton.icon(
              onPressed: _busy ? null : _leave,
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Finish this later'),
            ),
            const SizedBox(height: Space.sm),
            Text(
              'Your account is already registered with the office and sits in '
              'their queue with whatever you have filled in. The rest of this is '
              'waiting for you under Account whenever you have it to hand.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('$completed OF $total STEPS DONE', style: palette.eyebrow)),
            if (completed == total)
              Icon(Icons.check_circle, size: 18, color: palette.success),
          ],
        ),
        const SizedBox(height: Space.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : completed / total,
            minHeight: 6,
            color: completed == total ? palette.success : palette.gold,
          ),
        ),
      ],
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
    final palette = context.palette;
    final theme = Theme.of(context);
    final missing = document == null;
    final expired = document?.isExpired ?? false;
    final tone = missing
        ? palette.inkSubtle
        : expired
            ? palette.danger
            : document!.status == 'approved'
                ? palette.success
                : palette.warning;

    final status = missing
        ? 'Not uploaded'
        : expired
            ? 'Expired ${formatDateTime(document!.expiryDate)}'
            : '${document!.status} · expires ${formatDateTime(document!.expiryDate)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: theme.textTheme.titleMedium),
                Text(status, style: theme.textTheme.bodySmall?.copyWith(color: tone)),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          OutlinedButton(
            onPressed: busy ? null : onUpload,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(88, 40),
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
            ),
            child: Text(missing ? 'Upload' : 'Replace'),
          ),
        ],
      ),
    );
  }
}
