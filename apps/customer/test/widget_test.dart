import 'package:flutter_test/flutter_test.dart';
import 'package:alteo_customer/main.dart';

void main() {
  testWidgets('customer home shows Alteo services and location prompt', (tester) async {
    await tester.pumpWidget(const AlteoCustomerApp());

    expect(find.text('DELIVERING TO'), findsOneWidget);
    expect(find.text('What do you need today?'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Quick'), findsOneWidget);
    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Set your delivery location'), findsOneWidget);
  });

  testWidgets('tapping a service clearly communicates it is not live yet', (tester) async {
    await tester.pumpWidget(const AlteoCustomerApp());

    await tester.tap(find.text('Food'));
    await tester.pump();

    expect(find.text('Food is coming soon to Alteo.'), findsOneWidget);
  });
}
