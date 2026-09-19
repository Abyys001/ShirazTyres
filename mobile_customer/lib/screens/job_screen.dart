import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/jobs.dart';
import '../widgets/cancel_call_out.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui_kit.dart';

/// Tracking (specification 4.6).
///
/// Status, the technician's first name, photograph and van, and a live ETA. No
/// map, and no position: the ETA is recalculated on the server and only the
/// figure is sent (4.6). Nothing on this screen identifies the driver beyond
/// what 4.7 allows.
///
/// The ETA and the rail are the screen. Everything that is a matter of record
/// rather than a matter of now — the request, the history, the bill — is folded
/// away behind one tap.
class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({required this.jobId, super.key});

  final int jobId;

  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
  bool _busy = false;

  Future<void> _cancel(CustomerJob job) async {
    setState(() => _busy = true);
    try {
      await confirmAndCancel(context, ref, job);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final job = ref.watch(jobProvider(widget.jobId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          job.valueOrNull?.reference ?? 'Your call-out',
          style: palette.mono.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: palette.ink),
        ),
      ),
      body: job.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Space.lg),
          child: LoadingBlock(count: 3),
        ),
        error: (error, __) => MessageView(
          title: 'Could not load this call-out',
          message: '$error',
          onRetry: () => ref.invalidate(jobProvider(widget.jobId)),
        ),
        data: _body,
      ),
      bottomNavigationBar: job.maybeWhen(
        data: (data) => data.canCancel
            ? StickyBar(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _cancel(data),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.danger,
                    side: BorderSide(color: palette.line),
                  ),
                  child: const Text('Cancel this call-out'),
                ),
              )
            : null,
        orElse: () => null,
      ),
    );
  }

  Widget _body(CustomerJob data) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final tone = palette.status(data.status);

    return RefreshIndicator(
      color: palette.gold,
      backgroundColor: palette.surfaceRaised,
      onRefresh: () async => ref.invalidate(jobProvider(widget.jobId)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
        children: <Widget>[
          SurfaceCard(
            accent: tone,
            wash: true,
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(status: data.status, label: data.statusDisplay, dense: true),
                ),
                const SizedBox(height: Space.lg),
                if (data.etaMinutes != null && data.isLive)
                  HeroFigure(
                    value: '${data.etaMinutes}',
                    unit: 'min away',
                    caption: 'Updated ${formatRelative(data.etaUpdatedAt)}',
                    tone: palette.gold,
                  )
                else ...<Widget>[
                  Text(data.headline, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: Space.xs),
                  Text(data.blurb, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: Space.xl),
                ProgressRail(stages: CustomerJob.stages, reached: data.stage, tone: tone),
              ],
            ),
          ),

          if (data.driver != null) ...<Widget>[
            const SizedBox(height: Space.lg),
            _TechnicianCard(driver: data.driver!),
          ],

          const SizedBox(height: Space.lg),
          ExpandableCard(
            title: 'Your request',
            icon: Icons.description_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DetailRow(
                  'Registration',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PlateBadge(formatPlate(data.plate)),
                  ),
                ),
                DetailRow('Vehicle', value: data.vehicle?.description ?? ''),
                DetailRow('Problem', value: data.issueLabel),
                DetailRow('Tyre', value: data.tyreSize, mono: true),
                if (data.locationText.isNotEmpty) DetailRow('Where', value: data.locationText),
                DetailRow('Requested', value: formatDateTime(data.createdAt)),
                if (data.sizeWasOverridden) ...<Widget>[
                  const SizedBox(height: Space.sm),
                  InlineNotice.warning(
                    'You gave us ${data.customerTyreSize}. Our record showed '
                    '${data.lookedUpTyreSize.isEmpty ? "no size" : data.lookedUpTyreSize}.',
                  ),
                ],
              ],
            ),
          ),

          if (data.timeline.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.md),
            ExpandableCard(
              title: 'Full history',
              icon: Icons.schedule_outlined,
              child: _Timeline(entries: data.timeline),
            ),
          ],

          if (data.invoice != null) ...<Widget>[
            const SizedBox(height: Space.lg),
            const SectionHeader('Your bill'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final line in data.invoice!.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              line.description,
                              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                            ),
                          ),
                          Text('£${line.lineTotal}', style: palette.mono),
                        ],
                      ),
                    ),
                  const Divider(height: Space.xl),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'VAT at ${data.invoice!.vatRate}%',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text('£${data.invoice!.vatAmount}', style: palette.mono),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Row(
                    children: <Widget>[
                      Expanded(child: Text('Total', style: theme.textTheme.titleLarge)),
                      Text(
                        '£${data.invoice!.total}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFamily: Fonts.mono,
                          color: palette.gold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Who is coming, and the one way to reach them. The office number is a target,
/// not a sentence to read — the explanation of why it goes through the office
/// belongs nowhere near a customer waiting on a hard shoulder.
class _TechnicianCard extends StatelessWidget {
  const _TechnicianCard({required this.driver});

  final AssignedDriver driver;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return SurfaceCard(
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
                Text(driver.firstName, style: theme.textTheme.titleLarge),
                Text(
                  driver.vehicleDescription,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.sm),
                PlateBadge(formatPlate(driver.vehiclePlate), dense: true),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          QuickAction(
            label: 'Office',
            icon: Icons.phone,
            tone: palette.gold,
            onTap: () => launchUrl(Uri.parse('tel:${AppConfig.officePhone}')),
          ),
        ],
      ),
    );
  }
}

/// The job's history as a rail of dots — the shape says "these happened in this
/// order" faster than a list of timestamps does.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        for (var index = 0; index < entries.length; index++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(color: palette.gold, shape: BoxShape.circle),
                    ),
                    if (index < entries.length - 1)
                      const Expanded(child: VerticalDivider(width: 9, thickness: 1)),
                  ],
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: index < entries.length - 1 ? Space.lg : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(entries[index].label, style: theme.textTheme.titleMedium),
                        Text(formatDateTime(entries[index].at), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
