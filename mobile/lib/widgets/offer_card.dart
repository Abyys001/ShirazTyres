import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/offer.dart';
import 'ui_kit.dart';

/// One live offer. The countdown is the point: in selection mode the job goes to
/// whoever answers first, and in automatic mode silence escalates it (section 6.5).
/// So the clock is the loudest thing on the card, and it turns red as it runs out.
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
    final palette = context.palette;
    final job = widget.offer.job;
    final seconds = widget.offer.remaining.inSeconds;
    final urgent = seconds <= 15;
    final tone = urgent ? palette.danger : palette.gold;
    final theme = Theme.of(context);

    final total = widget.offer.total.inSeconds;
    final fraction = total <= 0 ? 0.0 : (seconds / total).clamp(0.0, 1.0);

    return SurfaceCard(
      accent: tone,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.card)),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              color: tone,
              backgroundColor: palette.surfaceRaised,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('NEW OFFER', style: palette.eyebrow),
                          const SizedBox(height: 2),
                          Text(
                            job?.issueHeadline ?? 'New job',
                            style: theme.textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(color: tone.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        '${seconds}s',
                        style: TextStyle(
                          fontFamily: Fonts.mono,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                    ),
                  ],
                ),

                if (job != null) ...<Widget>[
                  const SizedBox(height: Space.md),
                  Row(
                    children: <Widget>[
                      PlateBadge(formatPlate(job.plate), dense: true),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          job.vehicle?.description ?? '',
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (job.tyreSize.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Space.sm),
                    // A customer-supplied size is what decides which tyre goes in
                    // the van, so it is flagged rather than mixed in with the rest.
                    job.sizeFromCustomer
                        ? InlineNotice.warning('Tyre ${job.tyreSize} — customer\'s own size.')
                        : Row(
                            children: <Widget>[
                              Icon(Icons.donut_large, size: 15, color: palette.inkSubtle),
                              const SizedBox(width: 6),
                              Text('Tyre ${job.tyreSize}', style: theme.textTheme.bodyMedium),
                            ],
                          ),
                  ],
                  const SizedBox(height: Space.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.place_outlined, size: 15, color: palette.inkSubtle),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          job.locationText.isEmpty
                              ? 'Location shared by the customer'
                              : job.locationText,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],

                if (widget.offer.etaMinutes != null || widget.offer.distanceMetres != null) ...<Widget>[
                  const SizedBox(height: Space.lg),
                  Row(
                    children: <Widget>[
                      if (widget.offer.etaMinutes != null)
                        Expanded(
                          child: StatBlock(
                            value: '${widget.offer.etaMinutes}',
                            label: 'min away',
                          ),
                        ),
                      if (widget.offer.distanceMetres != null)
                        Expanded(
                          child: StatBlock(
                            value: (widget.offer.distanceMetres! / 1000).toStringAsFixed(1),
                            label: 'km',
                          ),
                        ),
                    ],
                  ),
                ],

                // Taking the job is the whole point of the card, so it gets the
                // full width and the height of two ordinary buttons. Passing is
                // deliberately the smaller target: a mis-tap there costs the
                // technician the work and the customer the wait.
                const SizedBox(height: Space.lg),
                FilledButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () {
                          Buzz.commit();
                          widget.onAccept();
                        },
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                  icon: const Icon(Icons.check, size: 22),
                  label: const Text('Accept'),
                ),
                Center(
                  child: TextButton(
                    onPressed: widget.busy
                        ? null
                        : () {
                            Buzz.tap();
                            widget.onReject();
                          },
                    style: TextButton.styleFrom(foregroundColor: palette.inkSubtle),
                    child: const Text('Pass'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
