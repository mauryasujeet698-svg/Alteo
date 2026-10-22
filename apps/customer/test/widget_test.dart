import 'package:flutter_test/flutter_test.dart';
import 'package:alteo_customer/main.dart';

void main() {
  testWidgets('customer home shows Alteo services and location prompt', (tester) async {
    await tester.pumpWidget(const AlteoCustomerApp());

    expect(find.text('DELIVERING TO'), findsOneWidget);
    expect(find.text('What do you need today?'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Quick'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Rides'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Rides'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Set your delivery location'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Set your delivery location'), findsOneWidget);
  });

  testWidgets('tapping a service opens its browse page', (tester) async {
    await tester.pumpWidget(const AlteoCustomerApp());

    await tester.ensureVisible(find.text('Food'));
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    expect(find.text('Good food, made easy'), findsOneWidget);
    expect(find.text('Restaurants'), findsOneWidget);
  });
}
