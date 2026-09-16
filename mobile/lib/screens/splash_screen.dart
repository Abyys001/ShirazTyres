import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/auth.dart';
import '../widgets/brand_logo.dart';

/// How long a cold start may sit here before it has to explain itself. The API
/// client gives up after 20 seconds, so anything past that is not the network.
const _patience = Duration(seconds: 25);

/// Shown only while the stored session is being checked against the API. Brief,
/// but it is the first frame of the app — so it is the launcher tile, still
/// turning, rather than a spinner on black.
///
/// It also refuses to spin forever. A splash with no exit is the worst screen in
/// an app: the driver cannot report it, cannot retry it, and cannot get to the
/// phone screen to sign in again. After [_patience] it says what it is waiting
/// for and offers both.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _watchdog;
  bool _stalled = false;

  @override
  void initState() {
    super.initState();
    _watchdog = Timer(_patience, () {
      if (mounted) setState(() => _stalled = true);
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _retry() {
    setState(() => _stalled = false);
    _watchdog?.cancel();
    _watchdog = Timer(_patience, () {
      if (mounted) setState(() => _stalled = true);
    });
    unawaited(ref.read(authControllerProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: palette.wash),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BrandLogo(height: 96),
                const SizedBox(height: Space.xl),
                Text('ShirazTyres', style: theme.textTheme.displaySmall),
                // The logo does not turn, so the wait needs its own sign of life.
                if (!_stalled) ...<Widget>[
                  const SizedBox(height: Space.xl),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: palette.gold,
                      backgroundColor: palette.surfaceRaised,
                    ),
                  ),
                ],
                if (_stalled) ...<Widget>[
                  const SizedBox(height: Space.lg),
                  Text(
                    'Still trying to reach ShirazTyres.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Space.lg),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh, size: 19),
                    label: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Sign in again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
