import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/geo.dart';
import '../core/theme.dart';
import '../models/driver.dart';
import '../models/job.dart';
import '../models/offer.dart';
import '../providers/auth.dart';
import '../providers/jobs.dart';
import '../providers/location.dart';
import '../widgets/board_card.dart';
import '../widgets/map_view.dart';
import '../widgets/message_view.dart';
import '../widgets/offer_card.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui_kit.dart';
import 'location_picker_screen.dart';

/// The shift screen: online toggle, the job in hand, and any live offers.
///
/// One question at a time, in the order the shift asks them — am I online, what
/// am I on, what is being offered.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;
  Set<int> _announced = const <int>{};

  Future<void> _toggle(bool online) async {
    Buzz.commit();
    setState(() => _busy = true);
    final problem = await ref.read(availabilityProvider.notifier).setOnline(online);
    if (mounted) {
      setState(() => _busy = false);
      // Nine times in ten a failed start is the handset refusing a fix, and the
      // map is the way back on shift rather than an error to read twice.
      if (problem != null) _say(problem, offerPin: online);
    }
  }

  /// Section 11.1 wants a position on every ping, not a particular source for
  /// it. A driver whose phone will not locate itself stands the van on the map
  /// and goes on shift anyway.
  Future<void> _pin({bool thenGoOnline = false}) async {
    final picked = await pickLocation(
      context,
      initial: ref.read(manualPositionProvider),
      title: 'Where is the van?',
      prompt: 'Drag the map until the pin is on your van.',
      confirmLabel: thenGoOnline ? 'Start my shift here' : 'This is where I am',
      askForNote: false,
    );
    if (picked == null || !mounted) return;
    ref.read(manualPositionProvider.notifier).set(picked.point);
    if (thenGoOnline) await _toggle(true);
  }

  Future<void> _answer(int jobId, {required bool accept}) async {
    setState(() => _busy = true);
    try {
      final offers = ref.read(offersProvider.notifier);
      if (accept) {
        await offers.accept(jobId);
      } else {
        await offers.reject(jobId);
      }
    } on ApiException catch (error) {
      _say(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Taking a job off the board. Somebody else may have taken it a second ago,
  /// which is an ordinary answer rather than a failure — the API says so and the
  /// list corrects itself.
  Future<void> _claim(int jobId) async {
    setState(() => _busy = true);
    try {
      await ref.read(availableJobsProvider.notifier).claim(jobId);
    } on ApiException catch (error) {
      _say(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Has anybody looked at me yet?" — the one thing a waiting technician wants
  /// to do, and the one thing the screen has to answer honestly.
  ///
  /// Approval usually arrives on the socket without anybody asking, but a phone
  /// that slept through it, or was out of signal when it landed, has no other
  /// way back. Saying nothing on an unchanged standing reads as a broken button,
  /// so the answer is always spoken either way.
  Future<void> _checkStanding() async {
    Buzz.tap();
    setState(() => _busy = true);
    final before = ref.read(currentDriverProvider)?.verificationStatus;
    await ref.read(authControllerProvider.notifier).refreshDriver();
    if (!mounted) return;
    setState(() => _busy = false);

    final driver = ref.read(currentDriverProvider);
    if (driver == null) return;
    if (driver.isApproved) {
      Buzz.alert();
      _say('You are approved. Go on shift to start taking jobs.');
    } else if (driver.verificationStatus != before) {
      _say(driver.statusDisplay);
    } else {
      _say('Still with the office. We will tell you the moment it changes.');
    }
  }

  void _say(String message, {bool offerPin = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: Duration(seconds: offerPin ? 8 : 4),
        action: offerPin
            ? SnackBarAction(label: 'Use the map', onPressed: () => _pin(thenGoOnline: true))
            : null,
      ));
  }

  /// A job arriving is the one event worth interrupting for. The phone is in a
  /// pocket or a cradle, so it buzzes rather than relying on being looked at.
  void _announce(List<Offer> offers) {
    final live = offers.where((offer) => offer.isLive).map((offer) => offer.id).toSet();
    if (live.difference(_announced).isNotEmpty) Buzz.alert();
    _announced = live;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final driver = ref.watch(currentDriverProvider);
    final availability = ref.watch(availabilityProvider);
    final online = availability.valueOrNull ?? false;
    final switching = _busy || availability.isLoading;
    final offers = ref.watch(offersProvider);
    final board = ref.watch(availableJobsProvider);
    final current = ref.watch(currentJobProvider);
    final pin = ref.watch(manualPositionProvider);

    ref.listen<AsyncValue<List<Offer>>>(offersProvider, (_, next) {
      final list = next.valueOrNull;
      if (list != null) _announce(list);
    });

    // A signed-in session whose profile would not load used to sit on a bare
    // spinner with nothing behind it — no error, no retry, no way to the rest of
    // the app. The session is real, so say what failed and offer the way out.
    if (driver == null) {
      final problem = ref.watch(authControllerProvider).error;
      return Scaffold(
        body: Center(
          child: problem == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: MessageView(
                    title: 'Could not load your profile',
                    message: problem,
                    icon: Icons.cloud_off,
                    onRetry: () =>
                        ref.read(authControllerProvider.notifier).restore(),
                  ),
                ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: Space.xl,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_greeting(), style: Theme.of(context).textTheme.bodySmall),
            Text(driver.name.isEmpty ? 'ShirazTyres' : driver.name.split(' ').first),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: palette.gold,
        backgroundColor: palette.surfaceRaised,
        onRefresh: () async {
          await ref.read(authControllerProvider.notifier).refreshDriver();
          await ref.read(offersProvider.notifier).refresh();
          await ref.read(availableJobsProvider.notifier).refresh();
          ref.read(jobRevisionProvider.notifier).state++;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxxl),
          children: <Widget>[
            // Until the office approves them, a technician has no shift, no
            // offers and no board — every one of those endpoints refuses them.
            // The whole screen is the standing, rather than the standing being
            // a banner above three empty lists that look like a fault.
            if (!driver.isApproved) ...<Widget>[
              const SizedBox(height: Space.sm),
              _StandingPanel(
                driver: driver,
                busy: _busy,
                onCheckAgain: _checkStanding,
              ),
            ],

            if (driver.isApproved) ...<Widget>[
              _ShiftSwitch(online: online, busy: switching, onChanged: _toggle),
              const SizedBox(height: Space.lg),
              if (pin != null) ...<Widget>[
                _PinnedNotice(
                  point: pin,
                  onMove: () => _pin(),
                  onClear: () => ref.read(manualPositionProvider.notifier).set(null),
                ),
                const SizedBox(height: Space.lg),
              ] else if (!online) ...<Widget>[
                Center(
                  child: TextButton.icon(
                    onPressed: switching ? null : () => _pin(),
                    icon: const Icon(Icons.pin_drop_outlined, size: 18),
                    label: const Text('No GPS? Set your position on the map'),
                  ),
                ),
                const SizedBox(height: Space.lg),
              ],
            ],

            if (driver.isApproved)
              current.when(
                data: (job) => job == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: Space.lg),
                        child: _CurrentJobCard(job: job),
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

            if (driver.isApproved)
              offers.when(
                data: (list) {
                  final live = list.where((offer) => offer.isLive).toList();
                  if (live.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SectionHeader('${live.length} live offer${live.length == 1 ? '' : 's'}'),
                      for (final offer in live)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: OfferCard(
                            offer: offer,
                            busy: _busy,
                            onAccept: () => _answer(offer.job?.id ?? 0, accept: true),
                            onReject: () => _answer(offer.job?.id ?? 0, accept: false),
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const LoadingBlock(),
                error: (error, __) => MessageView(
                  title: 'Could not load offers',
                  message: '$error',
                  onRetry: () => ref.read(offersProvider.notifier).refresh(),
                ),
              ),

            // Everything still waiting for somebody, offered or not. An offer
            // expires and vanishes with the round; this list is where the work
            // goes on sitting until a van takes it, so a shift is never staring
            // at an empty screen while customers wait.
            if (driver.isApproved)
              board.when(
                data: (list) {
                  if (list.isEmpty) {
                    if (current.valueOrNull != null) return const SizedBox.shrink();
                    return online
                        ? const MessageView(
                            title: 'Nothing waiting',
                            message: 'The nearest job comes to you first, and anything '
                                'nobody has taken stays here.',
                            icon: Icons.hourglass_empty,
                          )
                        : const MessageView(
                            title: 'You are offline',
                            message: 'Go on shift to get offers.',
                            icon: Icons.nightlight_outlined,
                          );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SectionHeader(
                        '${list.length} job${list.length == 1 ? '' : 's'} waiting',
                      ),
                      for (final job in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: BoardCard(
                            job: job,
                            busy: _busy,
                            onClaim: () => _claim(job.id),
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const LoadingBlock(),
                error: (error, __) => MessageView(
                  title: 'Could not load available jobs',
                  message: '$error',
                  onRetry: () => ref.read(availableJobsProvider.notifier).refresh(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

/// What the panel is being told while the position is set by hand.
///
/// This is deliberately loud and permanently on screen. A stale pin reports a
/// van that is somewhere else, which is worse than no position at all, so the
/// way out of it is next to the reason for it.
class _PinnedNotice extends StatelessWidget {
  const _PinnedNotice({required this.point, required this.onMove, required this.onClear});

  final LatLng point;
  final VoidCallback onMove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SurfaceCard(
      accent: palette.warning,
      padding: const EdgeInsets.all(Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MiniMap(point: point, height: 132, onTap: onMove),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, 0),
            child: Row(
              children: <Widget>[
                Icon(Icons.pin_drop, size: 18, color: palette.warning),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Position set by hand',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(point.pretty, style: palette.mono),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: onMove,
                icon: const Icon(Icons.open_with, size: 18),
                label: const Text('Move it'),
              ),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('Back to GPS'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one control that decides whether the shift is running.
///
/// The whole card is the target — a 5mm switch is the wrong thing to ask a
/// gloved thumb for in the rain — and it says its state in two words rather than
/// a sentence. Online, it breathes: a ring pulses out of the badge, which is
/// visible from the passenger seat and answers "am I taking work" without
/// anything being read. What being online costs is on the profile screen.
class _ShiftSwitch extends StatefulWidget {
  const _ShiftSwitch({required this.online, required this.busy, required this.onChanged});

  final bool online;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  State<_ShiftSwitch> createState() => _ShiftSwitchState();
}

class _ShiftSwitchState extends State<_ShiftSwitch> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.online) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_ShiftSwitch old) {
    super.didUpdateWidget(old);
    if (widget.online == old.online) return;
    widget.online ? _pulse.repeat() : _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final tone = widget.online ? palette.success : palette.inkSubtle;

    return Material(
      color: Colors.transparent,
      borderRadius: Radii.cardShape,
      child: InkWell(
        borderRadius: Radii.cardShape,
        onTap: widget.busy ? null : () => widget.onChanged(!widget.online),
        child: AnimatedContainer(
          duration: Motion.normal,
          padding: const EdgeInsets.all(Space.xl),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: Radii.cardShape,
            border: Border.all(color: widget.online ? tone.withValues(alpha: 0.45) : palette.line),
            gradient: widget.online ? palette.wash : null,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    if (widget.online)
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Container(
                          width: 56 + 8 * _pulse.value,
                          height: 56 + 8 * _pulse.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: tone.withValues(alpha: 0.5 * (1 - _pulse.value)),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    AnimatedContainer(
                      duration: Motion.normal,
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: widget.online ? tone.withValues(alpha: 0.16) : palette.surfaceRaised,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.online ? tone : palette.lineStrong,
                          width: 2,
                        ),
                      ),
                      child: widget.busy
                          ? const Padding(
                              padding: EdgeInsets.all(15),
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Icon(
                              widget.online ? Icons.bolt : Icons.nightlight_round,
                              size: 27,
                              color: widget.online ? tone : palette.inkSubtle,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.online ? 'On shift' : 'Off shift',
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text(
                      widget.busy
                          ? (widget.online ? 'Ending your shift' : 'Starting your shift')
                          : (widget.online ? 'Taking jobs' : 'Tap to start'),
                      style: theme.textTheme.titleMedium?.copyWith(color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              IgnorePointer(
                child: Switch(
                  value: widget.online,
                  onChanged: widget.busy ? null : widget.onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a technician who cannot yet take work is waiting for, and on whom.
///
/// Registration (section 8.1) and the administrator's decision (8.2) are two
/// separate waits, and conflating them is the whole problem this screen exists
/// to fix. Somebody whose paperwork is in has nothing left to do and must be
/// told so plainly; somebody with a document outstanding has to be sent back to
/// onboarding. The screen therefore leads with whose move it is, then shows the
/// three stages so the wait has a shape, and only then explains itself.
class _StandingPanel extends StatelessWidget {
  const _StandingPanel({
    required this.driver,
    required this.busy,
    required this.onCheckAgain,
  });

  final Driver driver;
  final bool busy;
  final Future<void> Function() onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    final tone = driver.isRejected
        ? palette.danger
        : driver.isSuspended
            ? palette.danger
            : driver.awaitingReview
                ? palette.info
                : palette.warning;

    final ours = !driver.awaitingReview && !driver.isRejected;

    final (String title, String body, IconData icon) = switch (driver) {
      final d when d.isRejected => (
          'Application not approved',
          'The office has decided not to take this application forward. They can '
              'tell you why, and whether anything can be done about it.',
          Icons.do_not_disturb_on_outlined,
        ),
      final d when d.isSuspended => (
          'Account suspended',
          'You will not be offered jobs while this stands. It is usually a '
              'document that has run out — upload a current one and the office '
              'will review it.',
          Icons.block,
        ),
      final d when d.awaitingReview => (
          'Waiting for approval',
          'Everything we need from you is in. A manager at the office now checks '
              'new technicians before any work is sent out, and that is the only '
              'thing left. As soon as they approve you, offers and the open board '
              'appear on this screen and you can start accepting shifts.',
          Icons.hourglass_top,
        ),
      _ => (
          'Finish setting up',
          'The office cannot approve you until the rest of your registration is '
              'in. It takes a couple of minutes, and then your account goes to '
              'them for approval.',
          Icons.assignment_outlined,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SurfaceCard(
          accent: tone,
          wash: driver.awaitingReview,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _StandingBadge(icon: icon, tone: tone, waiting: driver.awaitingReview),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 2),
                        Text(
                          driver.isRejected
                              ? 'CLOSED'
                              : ours
                                  ? 'OVER TO YOU'
                                  : 'WITH THE OFFICE',
                          style: palette.eyebrow,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: Space.lg),
              ProgressRail(
                stages: const <String>['Signed in', 'Your details', 'Office check', 'On shift'],
                reached: driver.isRejected
                    ? 1
                    : driver.onboardingComplete
                        ? 3
                        : 2,
                tone: tone,
              ),

              const SizedBox(height: Space.lg),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),

              if (driver.verificationNote.isNotEmpty) ...<Widget>[
                const SizedBox(height: Space.lg),
                InlineNotice(
                  driver.verificationNote,
                  tone: tone,
                  icon: Icons.chat_bubble_outline,
                ),
              ],

              const SizedBox(height: Space.lg),
              if (ours)
                FilledButton.icon(
                  onPressed: () {
                    Buzz.tap();
                    context.push('/onboarding');
                  },
                  icon: const Icon(Icons.arrow_forward, size: 19),
                  label: Text(driver.isSuspended ? 'Upload a document' : 'Finish setting up'),
                )
              else
                BusyButton(
                  label: 'Check again',
                  busy: busy,
                  icon: Icons.refresh,
                  outlined: true,
                  onPressed: onCheckAgain,
                ),
            ],
          ),
        ),

        // The receipt for what was handed over. A wait with nothing to show for
        // it invites the same paperwork being uploaded a second time.
        if (!driver.isRejected) ...<Widget>[
          const SizedBox(height: Space.lg),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('WHAT THE OFFICE HAS', style: palette.eyebrow),
                const SizedBox(height: Space.md),
                _ChecklistRow(
                  label: 'Your name',
                  detail: driver.name.isEmpty ? 'Not given yet' : driver.name,
                  done: driver.name.isNotEmpty,
                ),
                _ChecklistRow(
                  label: 'Your van',
                  detail: driver.van?.title ?? 'No van registered yet',
                  done: driver.vehicles.isNotEmpty,
                ),
                _ChecklistRow(
                  label: 'Documents',
                  detail: driver.missingDocuments.isNotEmpty
                      ? 'Still needed: ${driver.missingDocuments.join(', ')}'
                      : driver.documentsInReview > 0
                          ? '${driver.documentsInReview} with the office for review'
                          : '${driver.documents.length} uploaded',
                  done: driver.missingDocuments.isEmpty,
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: Space.lg),
        Center(
          child: Text(
            driver.awaitingReview
                ? 'You do not have to keep this open — we will notify you.'
                : 'Your phone number is ${driver.phone}.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// The badge at the head of the standing card. It breathes while the wait is
/// somebody else's, which is the difference between "in hand" and "stuck".
class _StandingBadge extends StatefulWidget {
  const _StandingBadge({required this.icon, required this.tone, required this.waiting});

  final IconData icon;
  final Color tone;
  final bool waiting;

  @override
  State<_StandingBadge> createState() => _StandingBadgeState();
}

class _StandingBadgeState extends State<_StandingBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.waiting) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_StandingBadge old) {
    super.didUpdateWidget(old);
    if (widget.waiting == old.waiting) return;
    widget.waiting ? _pulse.repeat() : _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (widget.waiting)
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 48 + 8 * _pulse.value,
                height: 48 + 8 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.tone.withValues(alpha: 0.45 * (1 - _pulse.value)),
                    width: 2,
                  ),
                ),
              ),
            ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.tone.withValues(alpha: palette.isDark ? 0.18 : 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: widget.tone.withValues(alpha: 0.5), width: 2),
            ),
            child: Icon(widget.icon, size: 24, color: widget.tone),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label, required this.detail, required this.done});

  final String label;
  final String detail;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final tone = done ? palette.success : palette.warning;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 19,
            color: tone,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 1),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentJobCard extends StatelessWidget {
  const _CurrentJobCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return SurfaceCard(
      accent: palette.status(job.status),
      onTap: () => context.push('/jobs/${job.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('JOB IN HAND', style: palette.eyebrow)),
              StatusChip(status: job.status, label: JobStatus.label(job.status), dense: true),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(job.issueHeadline, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.sm),
          Row(
            children: <Widget>[
              PlateBadge(formatPlate(job.plate), dense: true),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  job.contactName,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.place_outlined, size: 15, color: palette.inkSubtle),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  job.locationText.isEmpty ? 'Position shared by the customer' : job.locationText,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: () {
              Buzz.tap();
              context.push('/jobs/${job.id}');
            },
            icon: const Icon(Icons.arrow_forward, size: 19),
            label: const Text('Open job'),
          ),
        ],
      ),
    );
  }
}
