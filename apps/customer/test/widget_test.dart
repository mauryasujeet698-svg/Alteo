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
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Orders'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('bottom navigation switches tabs without removing navigation', (tester) async {
    await tester.pumpWidget(const AlteoCustomerApp());
    await tester.tap(find.text('Food').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Explore the options below. Live availability, prices and bookings require the Alteo backend and participating local partners to be configured.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Profile').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Sign in / Sign up with Google'), findsOneWidget);
    expect(find.text('My orders'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
