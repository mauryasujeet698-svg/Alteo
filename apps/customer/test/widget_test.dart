import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alteo_customer/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-public-key-for-widget-tests',
    );
  });

  testWidgets('home and persistent bottom navigation render', (tester) async {
    await tester.pumpWidget(const AlteoCustomerApp());
    expect(find.text('DELIVERING TO'), findsOneWidget);
    expect(find.text('Explore services'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('bottom navigation switches tabs without removing navigation', (tester) async {
    await tester.pumpWidget(const AlteoCustomerApp());
    await tester.tap(find.text('Orders'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Your orders will appear here'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in / Create account'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
