import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alteo_admin/main.dart';

void main() {
  testWidgets('public exploration opens without authentication', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RoleExplorePage(backendReady: false)));
    expect(find.text('Explore features'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
