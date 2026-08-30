import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/config.dart';
import '../core/formatters.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';

/// Tracking (specification 4.6).
///
/// Status, the technician's first name, photograph and van, and a live ETA. No
/// map, and no position: the ETA is recalculated on the server and only the
/// figure is sent.
class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({required this.jobId, super.key});

  final int jobId;

  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
  bool _busy = false;

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this call-out?'),
        content: const Text('We will stop looking for a technician.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel it')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(cancelJobProvider)(widget.jobId, '');
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider(widget.jobId));
    // Keep the socket alive for as long as this screen is open.
    ref.watch(customerSocketProvider);

    return Scaffold(
      appBar: AppBar(title: Text(job.valueOrNull?.reference ?? 'Your call-out')),
      body: job.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, __) => MessageView(title: 'Could not load this call-out', message: '$error'),
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(data.headline, style: Theme.of(context).textTheme.titleLarge),
                ),
                StatusChip(status: data.status, label: data.statusDisplay),
              ],
            ),
            const SizedBox(height: 8),
            Text(data.blurb),

            if (data.etaMinutes != null && data.isLive) ...<Widget>[
              const SizedBox(height: 20),
              Text('${data.etaMinutes} min', style: Theme.of(context).textTheme.displayMedium),
              Text(
                'estimated arrival · updated ${formatRelative(data.etaUpdatedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],

            if (data.driver != null) ...<Widget>[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 32,
                        backgroundImage:
                            data.driver!.photo.isEmpty ? null : NetworkImage(data.driver!.photo),
                        child: data.driver!.photo.isEmpty ? const Icon(Icons.person_outline) : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              data.driver!.firstName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(data.driver!.vehicleDescription),
                            Text(
                              formatPlate(data.driver!.vehiclePlate),
                              style: const TextStyle(fontFeatures: <FontFeature>[]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Need to speak to your technician? Call the office on ${AppConfig.officePhone} and '
                  'we will pass a message on.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],

            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Your request', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text('${data.vehicle?.description ?? ''} ${formatPlate(data.plate)}'.trim()),
                    Text('${data.issueLabel} · tyre ${data.tyreSize}'),
                    if (data.locationText.isNotEmpty) Text(data.locationText),
                    Text('Requested ${formatDateTime(data.createdAt)}'),
                    if (data.sizeWasOverridden)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'You gave us the size ${data.customerTyreSize}. Our record showed '
                          '${data.lookedUpTyreSize.isEmpty ? "no size" : data.lookedUpTyreSize}.',
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            if (data.invoice != null) ...<Widget>[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Your bill', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      for (final line in data.invoice!.lines)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Expanded(child: Text(line.description)),
                            Text('£${line.lineTotal}'),
                          ],
                        ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text('VAT at ${data.invoice!.vatRate}%'),
                          Text('£${data.invoice!.vatAmount}'),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text('£${data.invoice!.total}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You pay once the work is finished.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (data.timeline.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Progress', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      for (final entry in data.timeline)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(entry.label),
                            Text(formatDateTime(entry.at)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],

            if (data.canCancel) ...<Widget>[
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _busy ? null : _cancel,
                child: const Text('Cancel this call-out'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
