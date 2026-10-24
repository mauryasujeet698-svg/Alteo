import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alteo_dark_store/main.dart';

void main() {
  testWidgets('dark store features can be explored without authentication', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RoleExplorePage(backendReady: false)));
    expect(find.text('Explore features'), findsOneWidget);
    expect(find.text('Stock overview'), findsOneWidget);
    expect(find.text('Picking queue'), findsOneWidget);
  });
}
