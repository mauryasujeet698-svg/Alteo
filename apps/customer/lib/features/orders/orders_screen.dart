import 'package:customer/core/config/app_config.dart';
import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/features/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isSupabaseConfigured) {
      return Scaffold(
        appBar: AppBar(title: Text('Your orders', style: Theme.of(context).textTheme.headlineMedium)),
        body: _AccountRequired(onSignIn: () => AuthService.showConfigurationMessage(context)),
      );
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = snapshot.data?.session?.user ?? Supabase.instance.client.auth.currentUser;
        return Scaffold(
          appBar: AppBar(title: Text('Your orders', style: Theme.of(context).textTheme.headlineMedium)),
          body: user == null
              ? _AccountRequired(onSignIn: () => AuthService.signIn(context))
              : const _BackendPending(),
        );
      },
    );
  }
}

class _AccountRequired extends StatelessWidget {
  const _AccountRequired({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: AlteoColors.mint, shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_outlined, color: AlteoColors.forest, size: 36),
            ),
            const SizedBox(height: 18),
            Text('Your orders, all together', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('Sign in to view your personal order history. You can keep exploring Alteo without an account.', textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => context.go('/explore'), child: const Text('Continue exploring')),
          ],
        ),
      ),
    );
  }
}

class _BackendPending extends StatelessWidget {
  const _BackendPending();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_sync_outlined, size: 42),
            const SizedBox(height: 14),
            Text('Order history is being connected', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Your private orders will appear here after the order API and database policies are implemented and tested.', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
