import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../models/booking.dart';
import '../providers/auth.dart';
import '../providers/bookings.dart';
import '../widgets/booking_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driver = ref.watch(currentDriverProvider);
    final bookings = ref.watch(myBookingsProvider);
    final active = ref.watch(activeBookingProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(driver == null ? 'ShirazTyres' : 'Hi, ${driver.displayName}'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.directions_car_outlined),
            tooltip: 'My vehicles',
            onPressed: () => context.push('/vehicles'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(myBookingsProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: <Widget>[
            if (active != null) _ActiveCallout(booking: active),
            if (active != null) const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Your call-outs', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => _call(context),
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Call us'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            bookings.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => MessageView(
                title: 'Could not load your call-outs',
                message: '$error',
                icon: Icons.wifi_off,
                onRetry: () => ref.read(myBookingsProvider.notifier).refresh(),
              ),
              data: (items) => items.isEmpty
                  ? const MessageView(
                      title: 'No call-outs yet',
                      message: 'Tap the button below if you need a tyre sorted.',
                      icon: Icons.tire_repair,
                    )
                  : Column(
                      children: <Widget>[
                        for (final booking in items) ...<Widget>[
                          BookingTile(
                            booking: booking,
                            onTap: () => context.push('/bookings/${booking.id}'),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push('/new'),
            icon: const Icon(Icons.add_alert),
            label: const Text('Request a call-out'),
          ),
        ),
      ),
    );
  }

  Future<void> _call(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: AppConfig.shopPhone);
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call us on ${AppConfig.shopPhone}')),
      );
    }
  }
}

class _ActiveCallout extends StatelessWidget {
  const _ActiveCallout({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Call-out in progress',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusChip(status: booking.status, label: booking.statusLabel),
              ],
            ),
            const SizedBox(height: 10),
            Text(booking.reference, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${booking.issueLabel} · ${booking.whereLabel}'),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => context.push('/bookings/${booking.id}'),
              icon: Icon(Icons.timeline, color: scheme.primary),
              label: const Text('Track this call-out'),
            ),
          ],
        ),
      ),
    );
  }
}
