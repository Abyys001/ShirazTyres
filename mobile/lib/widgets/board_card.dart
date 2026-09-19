import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/job.dart';
import 'ui_kit.dart';

/// One call-out on the open board.
///
/// Deliberately quieter than [OfferCard]: an offer is a question being put to
/// this technician and has a clock on it, while the board is a standing list
/// nobody is waiting on an answer to. What it does say loudly is how long the
/// customer has been waiting, because that is the only thing distinguishing one
/// of these from another.
class BoardCard extends StatelessWidget {
  const BoardCard({required this.job, required this.onClaim, this.busy = false, super.key});

  final Job job;
  final VoidCallback onClaim;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return SurfaceCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text(job.issueHeadline, style: theme.textTheme.titleMedium)),
              const SizedBox(width: Space.md),
              Text(
                _waited(job.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(color: palette.inkSubtle),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: <Widget>[
              PlateBadge(formatPlate(job.plate), dense: true),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  job.tyreSize.isEmpty ? (job.vehicle?.description ?? '') : job.tyreSize,
                  style: palette.mono.copyWith(color: palette.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.place_outlined, size: 15, color: palette.inkSubtle),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  job.locationText.isEmpty ? 'Location shared by the customer' : job.locationText,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () {
                    Buzz.commit();
                    onClaim();
                  },
            icon: const Icon(Icons.pan_tool_alt_outlined, size: 19),
            label: const Text('Take this job'),
          ),
        ],
      ),
    );
  }
}

/// How long the customer has been waiting, in the fewest words that are true.
String _waited(DateTime? since) {
  if (since == null) return '';
  final elapsed = DateTime.now().difference(since);
  if (elapsed.inMinutes < 1) return 'just in';
  if (elapsed.inMinutes < 60) return 'waiting ${elapsed.inMinutes} min';
  if (elapsed.inHours < 24) return 'waiting ${elapsed.inHours} h';
  return 'waiting since ${formatDateTime(since)}';
}
