import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/services/pos_api.dart';
import 'package:pos_app/ui/login_screen.dart';

void main() {
  testWidgets('sign-in screen provides username and password fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(api: PosApi(), onLogin: (_) {}),
      ),
    );

    expect(find.text('POS Transfer Center'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
