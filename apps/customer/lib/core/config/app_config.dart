/// Build-time configuration supplied using Dart defines.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const oauthRedirectUrl = String.fromEnvironment(
    'OAUTH_REDIRECT_URL',
    defaultValue: 'com.alteo.customer://login-callback/',
  );

  static bool get isSupabaseConfigured =>
      (supabaseUrl.startsWith('https://') &&
          supabasePublishableKey.startsWith('sb_publishable_')) ||
      (supabaseUrl.startsWith('https://') &&
          supabasePublishableKey.startsWith('eyJ'));
}
