import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Push is behind an interface so the app builds and runs with no Firebase
/// project attached. Wire [FcmPushService] (see mobile/README.md) once
/// google-services.json / GoogleService-Info.plist are in place.
abstract class PushService {
  Future<String?> deviceToken();
}

class NoopPushService implements PushService {
  const NoopPushService();

  @override
  Future<String?> deviceToken() async => null;
}

final pushServiceProvider = Provider<PushService>((ref) => const NoopPushService());
