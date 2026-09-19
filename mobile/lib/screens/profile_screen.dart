import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/driver.dart';
import '../providers/auth.dart';
import '../widgets/status_chip.dart';
import '../widgets/theme_switch.dart';
import '../widgets/ui_kit.dart';

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

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            name: _name.text.trim(),
            email: _email.text.trim(),
          );
      _say('Saved.');
    } on ApiException catch (error) {
      _say(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will stop receiving offers on this device until you sign in again.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) context.go('/phone');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final driver = ref.watch(currentDriverProvider);
    if (driver == null) {
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
                  radius: 30,
                  backgroundColor: palette.surfaceRaised,
                  backgroundImage: driver.photo.isEmpty ? null : NetworkImage(driver.photo),
                  child: driver.photo.isEmpty
                      ? Icon(Icons.person_outline, color: palette.inkSubtle)
                      : null,
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        driver.name.isEmpty ? 'Unnamed technician' : driver.name,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(driver.phone, style: palette.mono),
                      const SizedBox(height: Space.sm),
                      StatusChip(
                        status: driver.isApproved ? 'completed' : 'submitted',
                        label: driver.statusDisplay,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Registration leads the screen while it is unfinished, because this
          // is now the only place it is asked for: nothing redirects here, and
          // an approved technician can work with it outstanding. Somebody who
          // never opens this tab would otherwise never learn the office is
          // still waiting on their insurance.
          if (!driver.onboardingComplete) ...<Widget>[
            const SizedBox(height: Space.xl),
            const SectionHeader('Finish setting up'),
            _SetupCard(driver: driver),
          ],

          const SizedBox(height: Space.xl),
          const SectionHeader('Details'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
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
                BusyButton(label: 'Save', busy: _saving, onPressed: _save),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('Your van'),
          SurfaceCard(
            onTap: () => context.go('/vehicles'),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: driver.vehicles.isEmpty
                      ? Text('No van registered.', style: theme.textTheme.bodyMedium)
                      : Row(
                          children: <Widget>[
                            PlateBadge(formatPlate(driver.van!.plate), dense: true),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Text(
                                driver.van!.description,
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
                Icon(Icons.chevron_right, color: palette.inkSubtle),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('On shift'),
          const SurfaceCard(
            child: InlineNotice.info(
              'While you are on shift your position is shared with the office so jobs can be '
              'ranked by travel time. Off shift, nothing is tracked.',
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('Appearance'),
          // Every other heading on this screen sits on a card. This one did
          // not, so the label floated over a bare control with nothing under it
          // and the run of sections visibly broke at exactly this row.
          const SurfaceCard(child: ThemeChoice()),

          const SizedBox(height: Space.xl),
          const SectionHeader('Documents'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (driver.documents.isEmpty)
                  Text('Nothing uploaded yet.', style: theme.textTheme.bodyMedium)
                else
                  for (final document in driver.documents)
                    DetailRow(
                      document.typeDisplay,
                      child: Text(
                        document.isExpired
                            ? 'Expired ${formatDateTime(document.expiryDate)}'
                            : '${document.status} · expires ${formatDateTime(document.expiryDate)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: document.isExpired ? palette.danger : palette.inkMuted,
                        ),
                      ),
                    ),
                const SizedBox(height: Space.lg),
                OutlinedButton(
                  onPressed: () => context.push('/onboarding'),
                  child: const Text('Update documents'),
                ),
              ],
            ),
          ),

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
}

/// What the office is still missing, and the one button that fixes it.
///
/// Registration used to be a screen the app pushed you onto and would not let
/// you off. It is a section of the account now: the record has been with the
/// office since the first sign-in either way, and an approved technician takes
/// work whether or not this is finished — so holding the whole app hostage to
/// it bought nothing and cost a driver their first shift.
///
/// What it must not do is go quiet. Every outstanding item is named, in words
/// rather than API slugs, with a progress bar that makes "nearly there"
/// visible — because the one failure mode left is somebody assuming they have
/// finished and waiting on an approval that is not coming.
class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.driver});

  final Driver driver;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    final steps = <({String label, String detail, bool done})>[
      (
        label: 'Your name',
        detail: driver.name.isEmpty ? 'Not given yet' : driver.name,
        done: driver.name.isNotEmpty,
      ),
      (
        label: 'Your van',
        detail: driver.van?.title ?? 'No registration added yet',
        done: driver.vehicles.isNotEmpty,
      ),
      (
        label: 'Your documents',
        detail: driver.missingDocuments.isEmpty
            ? (driver.documentsInReview > 0
                ? '${driver.documentsInReview} with the office for review'
                : 'All in')
            : 'Still needed: ${driver.missingDocuments.map(Driver.documentLabel).join(', ')}',
        done: driver.missingDocuments.isEmpty,
      ),
    ];
    final done = steps.where((step) => step.done).length;

    return SurfaceCard(
      accent: palette.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$done OF ${steps.length} DONE',
                  style: palette.eyebrow,
                ),
              ),
              Text(
                driver.isApproved ? 'Not blocking your shift' : 'The office is waiting',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: done / steps.length,
              minHeight: 6,
              color: palette.gold,
            ),
          ),

          const SizedBox(height: Space.lg),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    step.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 19,
                    color: step.done ? palette.success : palette.warning,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(step.label, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 1),
                        Text(step.detail, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          Text(
            driver.isApproved
                ? 'You are approved and can go on shift now. The office would '
                    'still like the rest of this when you have a moment.'
                : 'Your account is registered with the office and in their queue '
                    'already. They can approve it as it stands, and are more '
                    'likely to once this is complete.',
            style: theme.textTheme.bodySmall,
          ),

          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: () {
              Buzz.tap();
              context.push('/onboarding');
            },
            icon: const Icon(Icons.arrow_forward, size: 19),
            label: const Text('Finish setting up'),
          ),
        ],
      ),
    );
  }
}
