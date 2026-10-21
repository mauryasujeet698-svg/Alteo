import 'package:customer/core/config/app_config.dart';
import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/features/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isSupabaseConfigured) {
      return _ProfilePage(
        displayName: 'Guest customer',
        subtitle: 'Explore first. Sign in when you are ready.',
        onSignIn: () => AuthService.showConfigurationMessage(context),
      );
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = snapshot.data?.session?.user ?? Supabase.instance.client.auth.currentUser;
        if (user == null) {
          return _ProfilePage(
            displayName: 'Guest customer',
            subtitle: 'Your account is only needed for personal features.',
            onSignIn: () => AuthService.signIn(context),
          );
        }
        return _ProfilePage(
          displayName: user.userMetadata?['full_name'] as String? ?? user.email ?? 'Alteo customer',
          subtitle: user.email ?? 'Signed in with Google',
          onSignOut: () => AuthService.signOut(context),
        );
      },
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.displayName,
    required this.subtitle,
    this.onSignIn,
    this.onSignOut,
  });

  final String displayName;
  final String subtitle;
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Profile', style: Theme.of(context).textTheme.headlineMedium)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(color: AlteoColors.mint, shape: BoxShape.circle),
                  child: const Icon(Icons.person_outline_rounded, color: AlteoColors.forest, size: 29),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 3),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onSignIn != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 8),
            Text(
              'Google sign-in becomes active after Supabase Auth and the mobile redirect are configured. Browsing stays open.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          Text('YOUR ACCOUNT', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const _ProfileRow(icon: Icons.receipt_long_outlined, title: 'My orders', subtitle: 'Order history and refunds'),
          const _ProfileRow(icon: Icons.location_on_outlined, title: 'Saved addresses', subtitle: 'Home, work and other places'),
          const _ProfileRow(icon: Icons.favorite_border_rounded, title: 'Favourites', subtitle: 'Products and restaurants you save'),
          const _ProfileRow(icon: Icons.account_balance_wallet_outlined, title: 'Payments', subtitle: 'Available methods will appear here'),
          const SizedBox(height: 18),
          Text('PREFERENCES & HELP', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const _ProfileRow(icon: Icons.notifications_none_rounded, title: 'Notifications', subtitle: 'Delivery and account updates'),
          const _ProfileRow(icon: Icons.dark_mode_outlined, title: 'Appearance', subtitle: 'Follows your device theme'),
          const _ProfileRow(icon: Icons.support_agent_rounded, title: 'Help & support', subtitle: 'Support options will be connected'),
          const _ProfileRow(icon: Icons.privacy_tip_outlined, title: 'Privacy & account security', subtitle: 'Manage your data and access'),
          if (onSignOut != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(title + ' will be enabled with the relevant backend module.')),
      ),
    );
  }
}
