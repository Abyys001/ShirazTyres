import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_customer/app.dart';

void main() {
  testWidgets('cold start with no stored token lands on sign-in', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await tester.pumpWidget(const ProviderScope(child: ShirazTyresCustomerApp()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Text me a code'), findsOneWidget);
  });
}
