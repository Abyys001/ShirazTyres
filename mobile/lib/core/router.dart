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
import '../screens/shell.dart';
import '../screens/splash_screen.dart';
import '../screens/vehicle_screen.dart';

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
        // Everybody lands on the shift screen. Registration is no longer a gate
        // in front of the app: what is outstanding lives on the account screen,
        // which says so and offers the form, and what actually decides whether
        // work can be taken is the office's approval — which the shift screen
        // is the right place to be told about.
        //
        // A brand-new registration is walked straight to the form by the OTP
        // screen, which is an offer on the one occasion it is wanted rather
        // than a redirect that fires on every cold start afterwards.
        return '/';
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

      // Each destination keeps its own navigation stack and scroll position,
      // so switching tabs never loses where somebody was. The order here lines
      // up one-to-one with the bottom bar in AppShell.
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/vehicles', builder: (_, __) => const VehicleScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
            ],
          ),
        ],
      ),

      // Full-screen flows: a job in hand and the paperwork that gets you one
      // both want the whole phone.
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
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
