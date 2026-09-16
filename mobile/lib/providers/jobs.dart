import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/offer_socket.dart';
import '../models/invoice.dart';
import '../models/job.dart';
import '../models/offer.dart';
import 'api.dart';
import 'auth.dart';

/// Live offers (specification 6). Rebuilt whenever the socket says something
/// changed, and polled slowly as a backstop for a dropped connection.
final offersProvider = AsyncNotifierProvider<OffersController, List<Offer>>(OffersController.new);

class OffersController extends AsyncNotifier<List<Offer>> {
  Timer? _poll;
  bool _gone = false;

  @override
  Future<List<Offer>> build() async {
    _gone = false;
    final socket = ref.watch(driverSocketProvider);
    final subscription = socket.events.listen((event) {
      final name = '${event['event']}';
      if (name.startsWith('offer.') || name.startsWith('job.')) {
        unawaited(refresh());
      }
    });

    // The socket carries every offer; this is the backstop for a dropped
    // connection, and it leans on the poll harder while the socket is down.
    final connection = socket.connection.listen((up) {
      _poll?.cancel();
      _poll = Timer.periodic(
        up ? const Duration(seconds: 30) : const Duration(seconds: 10),
        (_) => unawaited(refresh()),
      );
      if (up) unawaited(refresh());
    });

    _poll = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(refresh()));
    ref.onDispose(() {
      _gone = true;
      subscription.cancel();
      connection.cancel();
      _poll?.cancel();
    });

    return ref.read(jobApiProvider).offers();
  }

  /// A refresh may correct the list; it must never replace a good one with an
  /// error because one poll could not reach the API mid-shift.
  Future<void> refresh() async {
    final result = await AsyncValue.guard(() => ref.read(jobApiProvider).offers());
    if (_gone) return;
    if (result.hasError && state.hasValue) return;
    state = result;
  }

  Future<void> accept(int jobId) async {
    await ref.read(jobApiProvider).accept(jobId);
    await refresh();
    ref.invalidate(currentJobProvider);
  }

  Future<void> reject(int jobId, {String reason = ''}) async {
    await ref.read(jobApiProvider).reject(jobId, reason: reason);
    await refresh();
    ref.invalidate(currentJobProvider);
  }
}

final driverSocketProvider = Provider<OfferSocket>((ref) {
  final socket = OfferSocket(
    () => ref.read(tokenStoreProvider).readAccess(),
    // The handshake carries the access token in the query string, so an expired
    // one is refused and no amount of retrying fixes it. One authenticated REST
    // call renews it through the client's interceptor; the next attempt then
    // carries a live token.
    onRefused: () => ref.read(driverApiProvider).meRaw(),
  );
  unawaited(socket.connect());
  ref.onDispose(socket.dispose);
  return socket;
});

/// The job in hand. A technician has at most one by default (`drivers.max_concurrent_jobs`).
final currentJobProvider = FutureProvider<Job?>((ref) async {
  ref.watch(jobRevisionProvider);
  final page = await ref.read(jobApiProvider).jobs();
  for (final job in page.results) {
    if (job.isLive) return job;
  }
  return null;
});

/// Bumped after any mutation so every watcher refetches once.
final jobRevisionProvider = StateProvider<int>((ref) => 0);

final jobHistoryProvider = FutureProvider<List<Job>>((ref) async {
  ref.watch(jobRevisionProvider);
  final page = await ref.read(jobApiProvider).jobs(status: 'completed');
  return page.results;
});

final jobProvider = FutureProvider.family<Job, int>((ref, id) {
  ref.watch(jobRevisionProvider);
  return ref.read(jobApiProvider).job(id);
});

final priceListProvider = FutureProvider<List<ServiceItem>>(
  (ref) => ref.read(jobApiProvider).priceList(),
);

/// One place for every write, so nothing forgets to invalidate.
class JobActions {
  const JobActions(this.ref);

  final Ref ref;

  Future<void> _bump() async {
    ref.read(jobRevisionProvider.notifier).state++;
  }

  Future<Job> advance(Job job) async {
    final next = job.nextStatus;
    if (next == null) return job;
    final updated = await ref.read(jobApiProvider).setStatus(job.id, next);
    await _bump();
    return updated;
  }

  Future<Job> correctTyre(int jobId, String size, {String note = ''}) async {
    final job = await ref.read(jobApiProvider).correctTyre(jobId, size, note: note);
    await _bump();
    return job;
  }

  Future<Invoice> addLine(int jobId, {int? serviceItemId, String description = '', String? unitPrice, String quantity = '1', String kind = 'part'}) async {
    final invoice = await ref.read(jobApiProvider).addLine(
          jobId,
          serviceItemId: serviceItemId,
          description: description,
          unitPrice: unitPrice,
          quantity: quantity,
          kind: kind,
        );
    await _bump();
    return invoice;
  }

  Future<Invoice> removeLine(int jobId, int lineId) async {
    final invoice = await ref.read(jobApiProvider).removeLine(jobId, lineId);
    await _bump();
    return invoice;
  }

  Future<Job> complete(int jobId, {String paymentMethod = '', String reference = ''}) async {
    final job = await ref.read(jobApiProvider).complete(
          jobId,
          paymentMethod: paymentMethod,
          reference: reference,
        );
    await _bump();
    return job;
  }
}

final jobActionsProvider = Provider<JobActions>(JobActions.new);

/// The app-wide bridge from the live channel to everything that reads a job.
///
/// [OffersController] listens for its own list, but the job in hand, the history
/// and the driver's own record are all separate providers that were only ever
/// refetched by a pull-to-refresh. One listener here bumps the revision every
/// watcher already keys off, so a status the office changed shows up on the
/// technician's phone without anybody touching the screen.
final driverLiveSyncProvider = Provider<void>((ref) {
  final subscription = ref.watch(driverSocketProvider).events.listen((event) {
    final name = '${event['event']}';
    if (name.startsWith('job.') || name.startsWith('offer.')) {
      ref.read(jobRevisionProvider.notifier).state++;
    }
    if (name.startsWith('driver.')) {
      // Approval, suspension, and the shift toggle the office can flip remotely.
      unawaited(ref.read(authControllerProvider.notifier).refreshDriver());
    }
  });
  ref.onDispose(subscription.cancel);
});
