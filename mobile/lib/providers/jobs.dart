import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/offer_socket.dart';
import '../models/invoice.dart';
import '../models/job.dart';
import '../models/offer.dart';
import 'api.dart';

/// Live offers (specification 6). Rebuilt whenever the socket says something
/// changed, and polled slowly as a backstop for a dropped connection.
final offersProvider = AsyncNotifierProvider<OffersController, List<Offer>>(OffersController.new);

class OffersController extends AsyncNotifier<List<Offer>> {
  Timer? _poll;

  @override
  Future<List<Offer>> build() async {
    final socket = ref.watch(driverSocketProvider);
    final subscription = socket.events.listen((event) {
      final name = '${event['event']}';
      if (name.startsWith('offer.') || name.startsWith('job.')) {
        refresh();
      }
    });

    _poll = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    ref.onDispose(() {
      subscription.cancel();
      _poll?.cancel();
    });

    return ref.read(jobApiProvider).offers();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(jobApiProvider).offers());
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
  final socket = OfferSocket(() => ref.read(tokenStoreProvider).readAccess());
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
