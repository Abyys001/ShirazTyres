import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';
import '../widgets/ui_kit.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final jobs = ref.watch(jobHistoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('My call-outs')),
      body: jobs.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Space.lg),
          child: LoadingBlock(count: 3),
        ),
        error: (error, __) => MessageView(
          title: 'Could not load your call-outs',
          message: '$error',
          onRetry: () => ref.invalidate(jobHistoryProvider),
        ),
        data: (list) => list.isEmpty
            ? MessageView(
                title: 'Nothing here yet',
                message: 'Every call-out shows up here, with its bill.',
                icon: Icons.history,
                action: FilledButton.icon(
                  onPressed: () => context.push('/request'),
                  icon: const Icon(Icons.bolt, size: 19),
                  label: const Text('Get help now'),
                ),
              )
            : RefreshIndicator(
                color: palette.gold,
                backgroundColor: palette.surfaceRaised,
                onRefresh: () async => ref.invalidate(jobHistoryProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxxl),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: Space.md),
                  itemBuilder: (context, index) {
                    final palette = context.palette;
                    final job = list[index];
                    return SurfaceCard(
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
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontFamily: Fonts.mono),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
