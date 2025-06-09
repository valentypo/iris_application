// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_application/screens/login_page.dart';

void main() {
  testWidgets('LoginPage loads smoke test', (WidgetTester tester) async {
    // Build the LoginPage inside a MaterialApp (as in main.dart)
    await tester.pumpWidget(MaterialApp(home: LoginPage()));

    // Check that the LoginPage is displayed (e.g., by finding the Login button)
    expect(find.text('Login'), findsOneWidget);
  });
}
