import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/invoice_screen.dart';
import '../screens/job_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/otp_screen.dart';
import '../screens/phone_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/splash_screen.dart';

/// Bridges Riverpod state onto go_router's Listenable-based refresh.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, __) => notifyListeners());
  }
}

final _authRefreshProvider = Provider<_AuthRefresh>((ref) => _AuthRefresh(ref));

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_authRefreshProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.matchedLocation;

      if (!auth.isResolved) {
        return path == '/splash' ? null : '/splash';
      }
      final onAuthScreen = path == '/phone' || path == '/otp';
      if (!auth.isSignedIn) {
        return onAuthScreen ? null : '/phone';
      }
      if (onAuthScreen || path == '/splash') {
        // A driver with paperwork outstanding starts where the work is.
        return auth.needsOnboarding ? '/onboarding' : '/';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final args = state.extra is Map ? state.extra! as Map : const <dynamic, dynamic>{};
          return OtpScreen(
            phone: '${args['phone'] ?? ''}',
            resendAfterSeconds: args['resendAfter'] is int ? args['resendAfter'] as int : 60,
            debugCode: '${args['debugCode'] ?? ''}',
          );
        },
      ),
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/jobs/:id',
        builder: (_, state) => JobScreen(jobId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
      ),
      GoRoute(
        path: '/jobs/:id/invoice',
        builder: (_, state) =>
            InvoiceScreen(jobId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
      ),
    ],
  );
});
