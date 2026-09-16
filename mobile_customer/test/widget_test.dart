import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_customer/app.dart';
import 'package:shiraztyres_customer/screens/sign_in_screen.dart';
import 'package:shiraztyres_customer/screens/splash_screen.dart';

/// The splash and sign-in screens both carry looping animations — the backdrop
/// drifts, the mark turns — so there is never a settled frame to wait for.
/// Advancing a fixed slice is the correct wait here; `pumpAndSettle` would sit
/// there until it timed out.
Future<void> advance(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('cold start with no stored session lands on sign-in', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await tester.pumpWidget(const ProviderScope(child: ShirazTyresCustomerApp()));
    expect(find.byType(SplashScreen), findsOneWidget);

    await advance(tester);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Text me a code'), findsOneWidget);
  });

  testWidgets('sign-in asks for nothing but the number', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await tester.pumpWidget(const ProviderScope(child: ShirazTyresCustomerApp()));
    await advance(tester);

    // The code step does not exist until a code has been asked for, and the
    // name is not asked for here at all — it lives on the account screen.
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Your name'), findsNothing);
  });
}
