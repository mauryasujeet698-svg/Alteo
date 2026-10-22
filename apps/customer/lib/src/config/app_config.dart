class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.mapboxPublicToken,
    required this.cloudinaryCloudName,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String mapboxPublicToken;
  final String cloudinaryCloudName;

  // These are public client configuration values, protected by Supabase RLS.
  // CI dart-defines can override them for staging or production environments.
  factory AppConfig.fromEnvironment() => const AppConfig(
        supabaseUrl: String.fromEnvironment(
          'SUPABASE_URL',
          defaultValue: 'https://nkerkoptbrcadlpxffkn.supabase.co',
        ),
        supabaseAnonKey: String.fromEnvironment(
          'SUPABASE_ANON_KEY',
          defaultValue: 'sb_publishable_lM6ttzw8KMPH2BNXgMAJVA_3y1h51YD',
        ),
        mapboxPublicToken: String.fromEnvironment('MAPBOX_PUBLIC_TOKEN'),
        cloudinaryCloudName: String.fromEnvironment('CLOUDINARY_CLOUD_NAME'),
      );
}