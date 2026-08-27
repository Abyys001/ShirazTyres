import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../models/booking.dart';
import 'status_chip.dart';

class BookingTile extends StatelessWidget {
  const BookingTile({required this.booking, required this.onTap, super.key});

  final Booking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      booking.reference,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  StatusChip(status: booking.status, label: booking.statusLabel),
                ],
              ),
              const SizedBox(height: 6),
              Text('${booking.issueLabel} · ${formatPlate(booking.plate)}'),
              const SizedBox(height: 2),
              Text(
                booking.whereLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                formatRelative(booking.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
