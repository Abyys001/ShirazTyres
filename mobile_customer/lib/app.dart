import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'providers/jobs.dart';
import 'providers/settings.dart';

class ShirazTyresCustomerApp extends ConsumerWidget {
  const ShirazTyresCustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Held for the life of the app: the live channel has to keep feeding the rest
    // of the providers whichever screen happens to be on top.
    ref.watch(customerLiveSyncProvider);

    return MaterialApp.router(
      title: 'ShirazTyres',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      // Long enough to read as a change of light rather than a glitch, short
      // enough that nobody waits for it.
      themeAnimationDuration: Motion.slow,
      themeAnimationCurve: Curves.easeOutCubic,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
