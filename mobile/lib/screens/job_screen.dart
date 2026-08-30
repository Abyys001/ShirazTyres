import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../models/job.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';
import 'invoice_screen.dart';

/// One job, from accepted to paid (specification 5 and 7).
class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({required this.jobId, super.key});

  final int jobId;

  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correctTyre(Job job) async {
    final controller = TextEditingController(text: job.tyreSize);
    final size = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct the tyre size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Use what is actually on the car. The office and the customer record both update.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Tyre size'),
              autofocus: true,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (size != null && size.isNotEmpty) {
      await _run(() => ref.read(jobActionsProvider).correctTyre(job.id, size));
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider(widget.jobId));

    return Scaffold(
      appBar: AppBar(title: Text(job.valueOrNull?.reference ?? 'Job')),
      body: job.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, __) => MessageView(
          title: 'Could not load this job',
          message: '$error',
          onRetry: () => ref.invalidate(jobProvider(widget.jobId)),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(data.issueLabel, style: Theme.of(context).textTheme.titleLarge),
                ),
                StatusChip(status: data.status, label: JobStatus.label(data.status)),
              ],
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Vehicle', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text('${data.vehicle?.description ?? ''} ${formatPlate(data.plate)}'.trim()),
                    const SizedBox(height: 10),
                    Text('Tyre', style: Theme.of(context).textTheme.titleSmall),
                    Text(data.tyreSize.isEmpty ? 'not recorded' : data.tyreSize),
                    if (data.sizeFromCustomer)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'The customer gave this size themselves. Our lookup said '
                          '${data.lookedUpTyreSize.isEmpty ? "nothing" : data.lookedUpTyreSize}.',
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    if (data.correctedOnSite)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Corrected on site.'),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _correctTyre(data),
                      child: const Text('The car does not match'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Customer', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(data.contactName),
                    Text(data.locationText.isEmpty ? 'Position shared' : data.locationText),
                    if (data.description.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(data.description),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.phone_outlined),
                            label: const Text('Call'),
                            onPressed: () => launchUrl(Uri.parse('tel:${data.contactPhone}')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.navigation_outlined),
                            label: const Text('Navigate'),
                            onPressed: data.mapsUrl.isEmpty
                                ? null
                                : () => launchUrl(
                                      Uri.parse(data.mapsUrl),
                                      mode: LaunchMode.externalApplication,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (data.nextStatus != null)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await ref.read(jobActionsProvider).advance(data);
                        }),
                child: Text(JobStatus.actionLabel(data.nextStatus!)),
              ),

            if (data.status == JobStatus.inProgress) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => InvoiceScreen(jobId: data.id),
                          ),
                        ),
                child: const Text('Invoice and payment'),
              ),
            ],

            if (data.status == JobStatus.completed) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Completed. Total ${data.invoice?.total ?? '—'}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
