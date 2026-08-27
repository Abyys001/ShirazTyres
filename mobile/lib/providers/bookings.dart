import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/booking.dart';
import 'api.dart';
import 'auth.dart';

/// The driver's own call-outs. Re-fetched whenever the session changes so a
/// second driver on the same handset never sees the first one's jobs.
class MyBookingsController extends AsyncNotifier<List<Booking>> {
  @override
  Future<List<Booking>> build() async {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isSignedIn) {
      return const <Booking>[];
    }
    final page = await ref.read(bookingApiProvider).myBookings();
    return page.results;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final page = await ref.read(bookingApiProvider).myBookings();
      return page.results;
    });
  }

  /// Put a freshly created call-out at the top without a round trip.
  void prepend(Booking booking) {
    final current = state.valueOrNull ?? const <Booking>[];
    state = AsyncValue<List<Booking>>.data(<Booking>[booking, ...current]);
  }
}

final myBookingsProvider =
    AsyncNotifierProvider<MyBookingsController, List<Booking>>(MyBookingsController.new);

final activeBookingProvider = Provider<Booking?>((ref) {
  final bookings = ref.watch(myBookingsProvider).valueOrNull ?? const <Booking>[];
  for (final booking in bookings) {
    if (booking.isOpen) return booking;
  }
  return null;
});

final bookingDetailProvider = FutureProvider.autoDispose.family<Booking, int>(
  (ref, id) => ref.watch(bookingApiProvider).booking(id),
);
