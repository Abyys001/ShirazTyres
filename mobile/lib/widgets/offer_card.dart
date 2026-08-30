import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../models/offer.dart';

/// One live offer. The countdown is the point: in selection mode the job goes to
/// whoever answers first, and in automatic mode silence escalates it (section 6.5).
class OfferCard extends StatefulWidget {
  const OfferCard({
    required this.offer,
    required this.onAccept,
    required this.onReject,
    this.busy = false,
    super.key,
  });

  final Offer offer;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool busy;

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.offer.job;
    final seconds = widget.offer.remaining.inSeconds;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    job?.issueLabel ?? 'New job',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: seconds <= 15
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${seconds}s', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (job != null) ...<Widget>[
              Text('${job.vehicle?.description ?? ''} ${formatPlate(job.plate)}'.trim()),
              if (job.tyreSize.isNotEmpty)
                Text(
                  'Tyre ${job.tyreSize}${job.sizeFromCustomer ? ' — customer supplied' : ''}',
                  style: TextStyle(
                    color: job.sizeFromCustomer ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 6),
              Text(job.locationText.isEmpty ? 'Location shared by the customer' : job.locationText),
            ],
            const SizedBox(height: 6),
            Text(
              <String>[
                if (widget.offer.etaMinutes != null) '${widget.offer.etaMinutes} min away',
                if (widget.offer.distanceMetres != null)
                  '${(widget.offer.distanceMetres! / 1000).toStringAsFixed(1)} km',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: widget.busy ? null : widget.onAccept,
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.busy ? null : widget.onReject,
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
