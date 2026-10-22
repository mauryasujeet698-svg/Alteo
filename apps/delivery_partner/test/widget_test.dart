import 'package:flutter_test/flutter_test.dart';
import 'package:alteo_delivery_partner/main.dart';

void main() {
  test('role app has the expected Supabase role guard', () {
    expect(appName, isNotEmpty);
    expect(requiredRole, isNotEmpty);
    expect(supabaseUrl, startsWith('https://'));
    expect(supabaseKey, isNotEmpty);
  });
}
