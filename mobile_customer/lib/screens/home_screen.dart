import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth.dart';
import '../providers/jobs.dart';
import '../widgets/brand_logo.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui_kit.dart';

/// Opens on the call-out in progress, if there is one, and otherwise on the one
/// button that starts one.
///
/// A customer with a flat tyre has exactly one question — "when" — and one thing
/// they want to do about it. The screen is those two things at full size, and
/// everything else is a tab away.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final customer = ref.watch(currentCustomerProvider);
    final active = ref.watch(activeJobProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: Space.xl,
        // The brand, not the customer: they know who they are, and seeing their
        // own name back is the one thing a header cannot tell them.
        title: Row(
          children: <Widget>[
            const BrandLogo(height: 30),
            const SizedBox(width: Space.md),
            Text('ShirazTyres', style: theme.textTheme.titleLarge),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: palette.gold,
        backgroundColor: palette.surfaceRaised,
        onRefresh: () => ref.read(activeJobProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xxxl),
          children: <Widget>[
            _Greeting(name: customer?.firstName ?? ''),
            const SizedBox(height: Space.xl),
            ...active.when(
              loading: () => const <Widget>[LoadingBlock(count: 1)],
              // Never a dead end. Losing the connection says nothing about
              // whether a technician is on their way, so the screen keeps doing
              // its job: it says it is out of touch, in one line, and leaves the
              // button that starts a call-out exactly where it was.
              error: (error, __) => <Widget>[
                _OfflineNotice(
                  message: '$error',
                  onRetry: () => ref.invalidate(activeJobProvider),
                ),
                const SizedBox(height: Space.lg),
                const _StartCard(),
              ],
              data: (state) => <Widget>[
                if (state.isStale) ...<Widget>[
                  _OfflineNotice(
                    message: 'Showing what we last heard, '
                        '${formatRelative(state.staleSince)}.',
                    onRetry: () => ref.read(activeJobProvider.notifier).refresh(),
                  ),
                  const SizedBox(height: Space.lg),
                ],
                if (state.job == null) ...<Widget>[
                  const _StartCard(),
                  const _LastCallOut(),
                ] else
                  _LiveJob(job: state.job!),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Two lines and no more. The point is to be greeted by name, not to be told
/// anything — so it says the time of day, says hello, and gets out of the way.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String name;

  static String _partOfDay(int hour) {
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 18) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(_partOfDay(DateTime.now().hour), style: context.palette.eyebrow),
        const SizedBox(height: Space.xs),
        Text(
          name.isEmpty ? 'Hi there' : 'Hi, $name',
          style: theme.textTheme.displaySmall,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// One line saying the app is out of touch, with the way back. Deliberately a
/// notice rather than a page: what it interrupts is worth more than it is.
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return InlineNotice.warning(
      message,
      action: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Try again'),
        ),
      ),
    );
  }
}

/// Nothing running: the screen is the button. Three icons underneath say what
/// the next two minutes look like, in three words each rather than three
/// sentences — enough to set expectations, not enough to read instead of tapping.
class _StartCard extends StatelessWidget {
  const _StartCard();

  static const _steps = <(IconData, String)>[
    (Icons.pin_outlined, 'Your reg'),
    (Icons.my_location, 'Your spot'),
    (Icons.local_shipping_outlined, 'We come'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return SurfaceCard(
      wash: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Flat tyre?', style: theme.textTheme.displaySmall),
          const SizedBox(height: Space.xs),
          Text('A technician comes to you.', style: theme.textTheme.bodyLarge),
          const SizedBox(height: Space.xl),
          FilledButton.icon(
            onPressed: () {
              Buzz.commit();
              context.push('/request');
            },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            icon: const Icon(Icons.bolt, size: 22),
            label: const Text('Get help now'),
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: <Widget>[
              for (var index = 0; index < _steps.length; index++) ...<Widget>[
                if (index > 0)
                  Icon(Icons.chevron_right, size: 16, color: palette.inkSubtle),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Icon(_steps[index].$1, size: 20, color: palette.gold),
                      const SizedBox(height: 6),
                      Text(
                        _steps[index].$2,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The call-out that finished, kept on the home screen rather than filed away.
///
/// Somebody who closed the app after a job and opened it again is usually
/// looking for that job — the bill, the date, who came — and making them find
/// the right tab first is a tax on the one thing they came back for. Absent
/// until there is one, so a new customer sees nothing.
class _LastCallOut extends ConsumerWidget {
  const _LastCallOut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobHistoryProvider).valueOrNull?.firstOrNull;
    if (job == null) return const SizedBox.shrink();

    final palette = context.palette;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: Space.xl),
        SectionHeader(
          'Last call-out',
          trailing: TextButton(
            onPressed: () => context.go('/history'),
            child: const Text('See all'),
          ),
        ),
        SurfaceCard(
          accent: palette.status(job.status),
          onTap: () => context.push('/jobs/${job.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(job.reference, style: palette.mono)),
                  StatusChip(status: job.status, label: job.headline, dense: true),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(job.issueHeadline, style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.sm),
              Row(
                children: <Widget>[
                  PlateBadge(formatPlate(job.plate), dense: true),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      formatDateTime(job.createdAt),
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (job.invoice != null)
                    Text(
                      '£${job.invoice!.total}',
                      style: theme.textTheme.titleMedium?.copyWith(fontFamily: Fonts.mono),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A call-out in flight. The ETA is the largest thing on the phone, the rail
/// under it says how far through we are, and one button opens the detail.
class _LiveJob extends StatelessWidget {
  const _LiveJob({required this.job});

  final CustomerJob job;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final tone = palette.status(job.status);

    return SurfaceCard(
      accent: tone,
      wash: true,
      padding: const EdgeInsets.all(Space.xl),
      onTap: () => context.push('/jobs/${job.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(status: job.status, label: job.headline, dense: true),
          ),
          const SizedBox(height: Space.lg),
          if (job.etaMinutes != null)
            HeroFigure(value: '${job.etaMinutes}', unit: 'min away', tone: palette.gold)
          else
            Text(job.headline, style: theme.textTheme.headlineMedium),
          const SizedBox(height: Space.xl),
          ProgressRail(stages: CustomerJob.stages, reached: job.stage, tone: tone),
          const SizedBox(height: Space.xl),
          Row(
            children: <Widget>[
              PlateBadge(formatPlate(job.plate), dense: true),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  job.issueHeadline,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: () => context.push('/jobs/${job.id}'),
            icon: const Icon(Icons.visibility_outlined, size: 19),
            label: const Text('Track'),
          ),
        ],
      ),
    );
  }
}
