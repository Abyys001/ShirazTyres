import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth.dart';
import '../screens/account_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/job_screen.dart';
import '../screens/request_screen.dart';
import '../screens/sign_in_screen.dart';
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
      if (!auth.isSignedIn) {
        return path == '/sign-in' ? null : '/sign-in';
      }
      if (path == '/sign-in' || path == '/splash') {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/request', builder: (_, __) => const RequestScreen()),
      GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
      GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
      GoRoute(
        path: '/jobs/:id',
        builder: (_, state) => JobScreen(jobId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
      ),
    ],
  );
});
