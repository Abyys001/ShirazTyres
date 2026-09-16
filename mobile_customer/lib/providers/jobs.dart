import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/job_socket.dart';
import '../models/job.dart';
import '../models/public_config.dart';
import 'api.dart';

final publicConfigProvider = FutureProvider<PublicConfig>(
  (ref) => ref.read(jobApiProvider).config(),
);

final customerSocketProvider = Provider<JobSocket>((ref) {
  final socket = JobSocket(
    () => ref.read(tokenStoreProvider).readAccess(),
    // The handshake carries the access token in the query string, so an expired
    // one is refused and no amount of retrying fixes it. One authenticated REST
    // call renews it through the client's interceptor; the next attempt then
    // carries a live token.
    onRefused: () => ref.read(authApiProvider).meRaw(),
  );
  unawaited(socket.connect());
  ref.onDispose(socket.dispose);
  return socket;
});

/// Bumped after a mutation so every watcher refetches once.
final jobRevisionProvider = StateProvider<int>((ref) => 0);

/// What the app opens on: the call-out in progress, if there is one.
final activeJobProvider = AsyncNotifierProvider<ActiveJobController, ActiveJob>(
  ActiveJobController.new,
);

/// A call-out plus how much we trust it.
///
/// The screen needs both: [job] is what to show, [staleSince] is whether to say
/// so. Folding "we could not reach the API" into an error state was what turned
/// a live call-out into an error page every time the signal dipped.
class ActiveJob {
  const ActiveJob({this.job, this.staleSince});

  const ActiveJob.none() : this();

  final CustomerJob? job;

  /// When the shown data was last confirmed, set only while we are failing to
  /// reach the API. Null means it is current.
  final DateTime? staleSince;

  bool get isStale => staleSince != null;
}

class ActiveJobController extends AsyncNotifier<ActiveJob> {
  bool _gone = false;

  @override
  Future<ActiveJob> build() async {
    _gone = false;

    // Watching the revision here rebuilt the whole controller — and with it the
    // socket subscription and the timer — every time anything bumped it. It is
    // listened to instead: a bump refreshes in place, which is what the screen
    // wants and what keeps the live call-out on screen while it happens.
    ref.listen<int>(jobRevisionProvider, (_, __) => unawaited(refresh()));

    // The socket carries the ETA; this is the fallback for a dropped connection,
    // and it polls harder while the connection is known to be down.
    final socket = ref.watch(customerSocketProvider);
    Timer? timer;
    void schedule({required bool live}) {
      timer?.cancel();
      timer = Timer.periodic(
        live ? const Duration(seconds: 30) : const Duration(seconds: 10),
        (_) => unawaited(refresh()),
      );
    }

    schedule(live: socket.isConnected);
    final connection = socket.connection.listen((up) {
      schedule(live: up);
      if (up) unawaited(refresh());
    });

    ref.onDispose(() {
      _gone = true;
      connection.cancel();
      timer?.cancel();
    });

    final cache = ref.read(jobCacheProvider);
    try {
      final raw = await ref.read(jobApiProvider).activeRaw();
      await cache.writeActive(raw);
      return ActiveJob(job: raw == null ? null : CustomerJob.fromJson(raw));
    } on ApiException {
      // A cold start with no signal opens on the call-out this phone last saw,
      // labelled as such, rather than on an apology.
      final cached = await cache.readActive();
      if (cached == null) rethrow;
      return ActiveJob(
        job: CustomerJob.fromJson(cached),
        staleSince: await cache.readStamp() ?? DateTime.now(),
      );
    }
  }

  /// A poll may correct what is on screen; it must never take it away. One
  /// dropped packet on the thirty-second tick used to replace a live call-out
  /// with an error screen, and every "try again" from there hit the same tick.
  /// A failure now keeps the last good answer and marks it stale.
  Future<void> refresh() async {
    final cache = ref.read(jobCacheProvider);
    try {
      final raw = await ref.read(jobApiProvider).activeRaw();
      if (_gone) return;
      await cache.writeActive(raw);
      state = AsyncValue<ActiveJob>.data(
        ActiveJob(job: raw == null ? null : CustomerJob.fromJson(raw)),
      );
    } catch (error, stack) {
      // Anything at all: the API refusing us, a payload this build cannot read,
      // the cache failing to open. None of them is a reason to take a live
      // call-out off the screen — it is marked stale and kept.
      if (_gone) return;
      final shown = state.valueOrNull;
      if (shown == null) {
        state = AsyncValue<ActiveJob>.error(error, stack);
        return;
      }
      state = AsyncValue<ActiveJob>.data(
        ActiveJob(
          job: shown.job,
          staleSince: shown.staleSince ?? await cache.readStamp() ?? DateTime.now(),
        ),
      );
    }
  }
}

final jobProvider = FutureProvider.family<CustomerJob, int>((ref, id) {
  ref.watch(jobRevisionProvider);
  return ref.read(jobApiProvider).job(id);
});

/// Every call-out this customer has had. Served from the device first when the
/// network will not answer, so the list is never empty on a phone that has
/// already seen it.
final jobHistoryProvider = FutureProvider<List<CustomerJob>>((ref) async {
  ref.watch(jobRevisionProvider);
  final cache = ref.read(jobCacheProvider);
  try {
    final raw = await ref.read(jobApiProvider).myJobsRaw();
    await cache.writeHistory(raw);
    return raw.map(CustomerJob.fromJson).toList();
  } on ApiException {
    final cached = await cache.readHistory();
    if (cached.isEmpty) rethrow;
    return cached.map(CustomerJob.fromJson).toList();
  }
});

final cancelJobProvider = Provider<Future<void> Function(int, String)>((ref) {
  return (int id, String reason) async {
    await ref.read(jobApiProvider).cancel(id, reason: reason);
    ref.read(jobRevisionProvider.notifier).state++;
  };
});

/// The app-wide bridge from the live channel to everything that reads a job.
///
/// [ActiveJobController] listens for the call-out in progress, but the job
/// screen and the history are separate providers that were only refetched by a
/// pull-to-refresh. One listener here bumps the revision they key off, so a
/// status change or a new ETA lands on whichever screen is open.
final customerLiveSyncProvider = Provider<void>((ref) {
  final subscription = ref.watch(customerSocketProvider).events.listen((event) {
    if ('${event['event']}'.startsWith('job.')) {
      ref.read(jobRevisionProvider.notifier).state++;
    }
  });
  ref.onDispose(subscription.cancel);
});
