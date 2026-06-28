import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_os/features/auth/login_screen.dart';

void main() {
  testWidgets('Login screen renders email, password and sign-in button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
