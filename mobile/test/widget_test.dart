import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_driver/api/dev_accounts_api.dart';
import 'package:shiraztyres_driver/app.dart';
import 'package:shiraztyres_driver/core/config.dart';
import 'package:shiraztyres_driver/providers/api.dart';
import 'package:shiraztyres_driver/screens/phone_screen.dart';
import 'package:shiraztyres_driver/screens/splash_screen.dart';

/// The panel fills itself from `GET /auth/dev/accounts`, which there is no
/// server to answer in a widget test. Overriding the provider keeps the test on
/// what it is actually about — that the panel opens and fills the field — rather
/// than on a network call that would always come back empty.
final _seeded = DevAccounts(
  accounts: const <DevAccount>[
    DevAccount('07700900301', 'Reza Karimi', 'approved'),
    DevAccount('07700900305', 'Nadia Farr', 'pending'),
  ],
  googleMock: '',
);

/// The splash and phone screens both carry looping animations — the backdrop
/// drifts, the mark turns — so there is never a settled frame to wait for.
/// Advancing a fixed slice is the correct wait here; `pumpAndSettle` would sit
/// there until it timed out.
Future<void> advance(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('cold start with no stored session lands on the phone screen',
      (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await tester.pumpWidget(const ProviderScope(child: ShirazTyresApp()));
    expect(find.byType(SplashScreen), findsOneWidget);

    await advance(tester);
    expect(find.byType(PhoneScreen), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('the phone screen offers the seeded accounts in a debug build',
      (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          devAccountsProvider.overrideWith((ref) async => _seeded),
        ],
        child: const ShirazTyresApp(),
      ),
    );
    await advance(tester);

    // Collapsed by default; the numbers only appear once it is opened.
    expect(find.text('07700900301'), findsNothing);
    await tester.ensureVisible(find.text('DEVELOPMENT SIGN-IN'));
    await tester.tap(find.text('DEVELOPMENT SIGN-IN'));
    await advance(tester);

    await tester.ensureVisible(find.text('07700900301'));
    await advance(tester);
    await tester.tap(find.text('07700900301'));
    await advance(tester);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller?.text,
      '07700900301',
    );
  });
}
