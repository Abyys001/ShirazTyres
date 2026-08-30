import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_driver/app.dart';

void main() {
  testWidgets('cold start with no stored token lands on the phone screen',
      (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await tester.pumpWidget(const ProviderScope(child: ShirazTyresApp()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });
}
