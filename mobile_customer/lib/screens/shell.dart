import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/ui_kit.dart';

/// Holds the four top-level destinations behind a persistent bottom bar.
///
/// Everything a customer can do is one thumb-reach from anywhere, and nothing
/// lives behind an icon in the top corner.
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  static const _items = <NavItem>[
    NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    NavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Call-outs'),
    NavItem(icon: Icons.directions_car_outlined, activeIcon: Icons.directions_car, label: 'Garage'),
    NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: AppNavBar(
        items: _items,
        index: shell.currentIndex,
        // Tapping the tab already showing pops it back to its root, which is
        // what every app with a tab bar has trained a thumb to expect.
        onSelect: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
      ),
    );
  }
}
