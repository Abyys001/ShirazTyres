import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/job_socket.dart';
import '../models/job.dart';
import '../models/public_config.dart';
import 'api.dart';

final publicConfigProvider = FutureProvider<PublicConfig>(
  (ref) => ref.read(jobApiProvider).config(),
);

final customerSocketProvider = Provider<JobSocket>((ref) {
  final socket = JobSocket(() => ref.read(tokenStoreProvider).readAccess());
  unawaited(socket.connect());
  ref.onDispose(socket.dispose);
  return socket;
});

/// Bumped after a mutation so every watcher refetches once.
final jobRevisionProvider = StateProvider<int>((ref) => 0);

/// What the app opens on: the call-out in progress, if there is one.
final activeJobProvider = AsyncNotifierProvider<ActiveJobController, CustomerJob?>(
  ActiveJobController.new,
);

class ActiveJobController extends AsyncNotifier<CustomerJob?> {
  @override
  Future<CustomerJob?> build() async {
    ref.watch(jobRevisionProvider);

    final subscription = ref.watch(customerSocketProvider).events.listen((event) {
      if ('${event['event']}'.startsWith('job.')) refresh();
    });
    // The socket carries the ETA; this is the fallback for a dropped connection.
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    ref.onDispose(() {
      subscription.cancel();
      timer.cancel();
    });

    return ref.read(jobApiProvider).active();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(jobApiProvider).active());
  }
}

final jobProvider = FutureProvider.family<CustomerJob, int>((ref, id) {
  ref.watch(jobRevisionProvider);
  return ref.read(jobApiProvider).job(id);
});

final jobHistoryProvider = FutureProvider<List<CustomerJob>>((ref) async {
  ref.watch(jobRevisionProvider);
  final page = await ref.read(jobApiProvider).myJobs();
  return page.results;
});

final cancelJobProvider = Provider<Future<void> Function(int, String)>((ref) {
  return (int id, String reason) async {
    await ref.read(jobApiProvider).cancel(id, reason: reason);
    ref.read(jobRevisionProvider.notifier).state++;
  };
});
