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
            // One question on this screen: may this technician take work? That
            // is the office's approval and nothing else — not whether the form
            // is finished, which lives on the account screen and does not stop
            // an approved driver going on shift.
            if (!driver.isApproved) ...<Widget>[
              const SizedBox(height: Space.sm),
              _ApprovalNotice(
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

/// Why there is no shift switch on this screen yet.
///
/// The only thing that decides it is section 8.2's approval. A technician the
/// office has approved goes on shift with an unfinished form and a van they
/// have not registered; one it has not approved cannot, however complete their
/// paperwork is. Those are two different waits and this screen owns exactly one
/// of them — what is outstanding on the form is the account screen's business,
/// and is mentioned here only as a pointer to it.
class _ApprovalNotice extends StatelessWidget {
  const _ApprovalNotice({
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

    final tone = driver.isRejected || driver.isSuspended ? palette.danger : palette.warning;

    final (String title, String body, IconData icon) = switch (driver) {
      final d when d.isRejected => (
          'Not approved',
          'The office has decided not to take this application forward, so no '
              'work can be sent to you. They can tell you why.',
          Icons.do_not_disturb_on_outlined,
        ),
      final d when d.isSuspended => (
          'Account suspended',
          'You cannot go on shift while this stands. It is usually a document '
              'that has run out — upload a current one from your account and the '
              'office will review it.',
          Icons.block,
        ),
      _ => (
          'Not approved yet',
          'The office has to approve your account before you can go on shift. '
              'Yours is registered with them and is in their queue. The moment '
              'they approve it the switch appears here and you can start taking '
              'jobs — we will notify you, so there is nothing to sit and watch.',
          Icons.hourglass_top,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SurfaceCard(
          accent: tone,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _WaitingBadge(icon: icon, tone: tone, waiting: driver.isPending),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('NO SHIFT AVAILABLE', style: palette.eyebrow),
                        const SizedBox(height: 2),
                        Text(title, style: theme.textTheme.headlineSmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),

              if (driver.verificationNote.isNotEmpty) ...<Widget>[
                const SizedBox(height: Space.lg),
                InlineNotice(
                  driver.verificationNote,
                  tone: tone,
                  icon: Icons.chat_bubble_outline,
                ),
              ],

              if (!driver.isRejected) ...<Widget>[
                const SizedBox(height: Space.lg),
                BusyButton(
                  label: 'Check again',
                  busy: busy,
                  icon: Icons.refresh,
                  outlined: true,
                  onPressed: onCheckAgain,
                ),
              ],
            ],
          ),
        ),

        // A nudge, not a gate. Nothing here blocks the shift switch appearing —
        // the office can approve an unfinished registration — but an approval
        // is less likely to come while the office is still missing things, so
        // it is worth saying once, on the screen they are waiting on.
        if (!driver.onboardingComplete && !driver.isRejected) ...<Widget>[
          const SizedBox(height: Space.lg),
          SurfaceCard(
            onTap: () => _openAccount(context),
            child: Row(
              children: <Widget>[
                Icon(Icons.assignment_outlined, size: 20, color: palette.inkSubtle),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Your registration is not finished', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'The office is still missing ${driver.outstanding.join(', ')}. '
                        'Finish it on your account screen.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: palette.inkSubtle),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The account tab, as a branch switch rather than a push, so it keeps the
  /// bottom bar and lands where the rest of the setup already is.
  void _openAccount(BuildContext context) {
    Buzz.tap();
    StatefulNavigationShell.of(context).goBranch(3);
  }
}

/// The badge at the head of the notice. It breathes while the wait is somebody
/// else's, which is the difference between "in hand" and "stuck".
class _WaitingBadge extends StatefulWidget {
  const _WaitingBadge({required this.icon, required this.tone, required this.waiting});

  final IconData icon;
  final Color tone;
  final bool waiting;

  @override
  State<_WaitingBadge> createState() => _WaitingBadgeState();
}

class _WaitingBadgeState extends State<_WaitingBadge> with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(_WaitingBadge old) {
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
