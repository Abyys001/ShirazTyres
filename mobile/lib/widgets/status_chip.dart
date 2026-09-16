import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The status of a job, everywhere it appears. The colour is drawn at 12% as a
/// background and full strength on the dot and label, which keeps the chip
/// legible without letting six of them turn a list into a rainbow.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, required this.label, this.dense = false, super.key});

  final String status;
  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colour = palette.status(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? Space.sm : Space.md, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: colour.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.sm),
          Text(
            label,
            style: TextStyle(
              fontFamily: Fonts.sans,
              color: colour,
              fontWeight: FontWeight.w600,
              fontSize: dense ? 11.5 : 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
