import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/booking.dart';
import '../providers/bookings.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';

class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({required this.bookingId, super.key});

  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingDetailProvider(bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Call-out')),
      body: booking.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => MessageView(
          title: 'Could not load this call-out',
          message: '$error',
          icon: Icons.wifi_off,
          onRetry: () => ref.invalidate(bookingDetailProvider(bookingId)),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(bookingDetailProvider(bookingId));
            await ref.read(myBookingsProvider.notifier).refresh();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              _Header(booking: data),
              const SizedBox(height: 20),
              _DetailCard(booking: data),
              const SizedBox(height: 20),
              Text('Progress', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _Timeline(events: data.statusEvents),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: AppConfig.shopPhone)),
                icon: const Icon(Icons.phone),
                label: const Text('Call the shop'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(booking.reference, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('Raised ${formatDateTime(booking.createdAt)}'),
            ],
          ),
        ),
        StatusChip(status: booking.status, label: booking.statusLabel),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _row('Problem', booking.issueLabel),
            _row('Vehicle', formatPlate(booking.plate)),
            if (booking.vehicle?.title.isNotEmpty ?? false) _row('Model', booking.vehicle!.title),
            if (booking.tyreSize.isNotEmpty) _row('Tyre size', booking.tyreSize),
            _row('Where', booking.whereLabel),
            if (booking.description.isNotEmpty) _row('Notes', booking.description),
            if (booking.mapsUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(booking.mapsUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open in Maps'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 90,
              child: Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<BookingStatusEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Text('No updates yet.');
    }
    return Column(
      children: <Widget>[
        for (final event in events)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.circle, size: 12, color: statusColour(event.toStatus)),
            title: Text(BookingStatus.label(event.toStatus)),
            subtitle: Text(
              <String>[
                formatDateTime(event.createdAt),
                if (event.changedByName.isNotEmpty) event.changedByName,
                if (event.note.isNotEmpty) event.note,
              ].join(' · '),
            ),
          ),
      ],
    );
  }
}
