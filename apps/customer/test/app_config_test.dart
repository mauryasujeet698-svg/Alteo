import 'package:flutter_test/flutter_test.dart';
import 'package:alteo_customer/src/config/app_config.dart';

void main() {
  test('environment configuration defaults to empty values', () {
    final config = AppConfig.fromEnvironment();
    expect(config.supabaseUrl, isA<String>());
    expect(config.supabaseAnonKey, isA<String>());
    expect(config.mapboxPublicToken, isA<String>());
    expect(config.cloudinaryCloudName, isA<String>());
  });
}
