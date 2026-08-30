import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatters.dart';
import '../models/job.dart';
import '../providers/auth.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';

/// Opens on the call-out in progress, if there is one, and otherwise invites a
/// new request.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(currentCustomerProvider);
    final active = ref.watch(activeJobProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(customer?.displayName ?? 'ShirazTyres'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/account'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(activeJobProvider.notifier).refresh(),
        child: active.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, __) => MessageView(
            title: 'Could not load your call-out',
            message: '$error',
            onRetry: () => ref.read(activeJobProvider.notifier).refresh(),
          ),
          data: (job) => ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (job == null) ...<Widget>[
                const SizedBox(height: 40),
                const MessageView(
                  title: 'No call-out in progress',
                  message: 'Tell us your registration and where you are, and we will send a technician.',
                  icon: Icons.tire_repair,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.push('/request'),
                  child: const Text('Request a technician'),
                ),
              ] else
                _ActiveJobCard(job: job),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  const _ActiveJobCard({required this.job});

  final CustomerJob job;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/jobs/${job.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(job.reference, style: Theme.of(context).textTheme.titleMedium)),
                  StatusChip(status: job.status, label: job.headline),
                ],
              ),
              const SizedBox(height: 8),
              Text(job.blurb),
              if (job.etaMinutes != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  '${job.etaMinutes} min',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Text('estimated arrival', style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              Text('${job.issueLabel} · ${formatPlate(job.plate)}'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/jobs/${job.id}'),
                child: const Text('Follow this call-out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
