import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alteo_seller/main.dart';

void main() {
  testWidgets('public exploration opens without authentication', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RoleExplorePage(backendReady: false)));
    expect(find.text('Explore features'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Product catalogue').first);
    await tester.pumpAndSettle();
    expect(find.text('Explore this screen'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('No sample records are shown. Your real data appears here after setup and authorised sign-in.'), findsWidgets);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Profile')));
    await tester.pumpAndSettle();
    expect(find.text('Profile & preferences'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
