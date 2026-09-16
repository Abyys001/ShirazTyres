import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';
import '../widgets/ui_kit.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final jobs = ref.watch(jobHistoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Completed jobs')),
      body: jobs.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Space.lg),
          child: LoadingBlock(count: 4),
        ),
        error: (error, __) => MessageView(
          title: 'Could not load your jobs',
          message: '$error',
          onRetry: () => ref.invalidate(jobHistoryProvider),
        ),
        data: (list) => list.isEmpty
            ? const MessageView(
                title: 'Nothing here yet',
                message: 'Jobs you finish and settle show up here with their invoice.',
                icon: Icons.history,
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
                      onTap: () => context.push('/jobs/${job.id}'),
                      padding: const EdgeInsets.all(Space.lg),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(job.reference, style: palette.mono),
                                const SizedBox(height: 2),
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
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (job.invoice != null)
                            Text(
                              '£${job.invoice!.total}',
                              style: theme.textTheme.titleLarge?.copyWith(fontFamily: Fonts.mono),
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
