import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../models/job.dart';
import '../providers/auth.dart';
import '../providers/jobs.dart';
import '../providers/location.dart';
import '../widgets/message_view.dart';
import '../widgets/offer_card.dart';
import '../widgets/status_chip.dart';

/// The shift screen: online toggle, the job in hand, and any live offers.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;

  Future<void> _toggle(bool online) async {
    setState(() => _busy = true);
    final problem = await ref.read(availabilityProvider.notifier).setOnline(online);
    if (mounted) {
      setState(() => _busy = false);
      if (problem != null) _say(problem);
    }
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

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(currentDriverProvider);
    final online = ref.watch(availabilityProvider).valueOrNull ?? false;
    final offers = ref.watch(offersProvider);
    final current = ref.watch(currentJobProvider);

    if (driver == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(driver.name.isEmpty ? 'ShirazTyres' : driver.name),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(authControllerProvider.notifier).refreshDriver();
          await ref.read(offersProvider.notifier).refresh();
          ref.read(jobRevisionProvider.notifier).state++;
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (!driver.isApproved) _VerificationNotice(driver: driver),
            if (driver.isApproved) ...<Widget>[
              Card(
                child: SwitchListTile(
                  value: online,
                  onChanged: _busy ? null : _toggle,
                  title: Text(online ? 'Online' : 'Offline'),
                  subtitle: Text(
                    online
                        ? 'You are in the dispatch pool and your position is being shared.'
                        : 'You will not be offered jobs, and nothing is tracked.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            current.when(
              data: (job) => job == null ? const SizedBox.shrink() : _CurrentJobCard(job: job),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            offers.when(
              data: (list) {
                final live = list.where((offer) => offer.isLive).toList();
                if (live.isEmpty) {
                  return current.valueOrNull == null && online
                      ? const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: MessageView(
                            title: 'Waiting for work',
                            message: 'You will be offered the nearest job as soon as one comes in.',
                            icon: Icons.hourglass_empty,
                          ),
                        )
                      : const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    Text('Offers', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (final offer in live)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
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
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, __) => MessageView(
                title: 'Could not load offers',
                message: '$error',
                onRetry: () => ref.read(offersProvider.notifier).refresh(),
              ),
            ),

            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => context.push('/history'),
              child: const Text('Completed jobs'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationNotice extends StatelessWidget {
  const _VerificationNotice({required this.driver});

  final dynamic driver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suspended = driver.isSuspended as bool;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              suspended ? 'Your account is suspended' : 'Waiting for approval',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              suspended
                  ? 'The office has taken you out of the pool. This happens automatically if your insurance '
                      'or licence lapses — upload a current document and the office will review it.'
                  : 'The office approves every technician before any work is sent out. '
                      'Finish your profile and documents and we will get you on the road.',
            ),
            if ((driver.verificationNote as String).isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(driver.verificationNote as String, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.push('/onboarding'),
              child: const Text('Finish setting up'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentJobCard extends StatelessWidget {
  const _CurrentJobCard({required this.job});

  final Job job;

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
                  StatusChip(status: job.status, label: JobStatus.label(job.status)),
                ],
              ),
              const SizedBox(height: 8),
              Text('${job.issueLabel} · ${job.contactName}'),
              Text(job.locationText.isEmpty ? 'Tap for directions' : job.locationText),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/jobs/${job.id}'),
                child: Text(job.nextStatus == null ? 'Open job' : JobStatus.actionLabel(job.nextStatus!)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
