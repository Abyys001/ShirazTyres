import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/ui_kit.dart';

/// Holds the four top-level destinations behind a persistent bottom bar.
///
/// A technician in gloves gets full-width targets rather than icons in the
/// top corner, and the shift toggle is never more than one tap away from
/// wherever they are.
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  static const _items = <NavItem>[
    NavItem(icon: Icons.bolt_outlined, activeIcon: Icons.bolt, label: 'Shift'),
    NavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Jobs'),
    NavItem(
      icon: Icons.directions_car_outlined,
      activeIcon: Icons.directions_car,
      label: 'Vehicles',
    ),
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
