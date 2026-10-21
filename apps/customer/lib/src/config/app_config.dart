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

  factory AppConfig.fromEnvironment() => const AppConfig(
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
        mapboxPublicToken: String.fromEnvironment('MAPBOX_PUBLIC_TOKEN'),
        cloudinaryCloudName: String.fromEnvironment('CLOUDINARY_CLOUD_NAME'),
      );
}
