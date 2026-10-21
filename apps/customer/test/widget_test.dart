import 'package:customer/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guest home renders without Supabase configuration', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: AlteoApp(),
      ),
    );

    expect(find.text('alteo'), findsOneWidget);
    expect(find.text('Choose your location'), findsOneWidget);
    expect(find.text('What do you need today?'), findsOneWidget);
  });
}
