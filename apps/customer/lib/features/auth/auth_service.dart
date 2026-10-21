import 'package:customer/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

abstract final class AuthService {
  static Future<void> signIn(BuildContext context) async {
    if (!AppConfig.isSupabaseConfigured) {
      showConfigurationMessage(context);
      return;
    }

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: AppConfig.oauthRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google sign-in could not start. Check your connection and try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static Future<void> signOut(BuildContext context) async {
    if (!AppConfig.isSupabaseConfigured) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign-out failed. Please try again.')),
      );
    }
  }

  static void showConfigurationMessage(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google sign-in setup pending'),
        content: const Text(
          'Guest browsing is available now. Google sign-in needs the Supabase Auth provider, OAuth redirect URL and mobile app configuration to be reviewed and enabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue browsing'),
          ),
        ],
      ),
    );
  }
}
