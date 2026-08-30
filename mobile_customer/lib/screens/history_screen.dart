import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatters.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My call-outs')),
      body: jobs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, __) => MessageView(
          title: 'Could not load your call-outs',
          message: '$error',
          onRetry: () => ref.invalidate(jobHistoryProvider),
        ),
        data: (list) => list.isEmpty
            ? const MessageView(title: 'Nothing here yet', icon: Icons.history)
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final job = list[index];
                  return ListTile(
                    title: Text('${job.reference} · ${job.issueLabel}'),
                    subtitle: Text(
                      '${formatPlate(job.plate)} · ${formatDateTime(job.createdAt)}',
                    ),
                    trailing: StatusChip(status: job.status, label: job.headline),
                    onTap: () => context.push('/jobs/${job.id}'),
                  );
                },
              ),
      ),
    );
  }
}
