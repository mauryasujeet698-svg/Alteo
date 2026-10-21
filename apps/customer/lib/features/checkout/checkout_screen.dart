import 'package:customer/core/config/app_config.dart';
import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/features/auth/auth_service.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CheckoutScreen extends ConsumerWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartStoreProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Checkout', style: Theme.of(context).textTheme.headlineMedium)),
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, child) {
          if (cart.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shopping_bag_outlined, size: 40),
                  const SizedBox(height: 12),
                  const Text('Your cart is empty.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => context.go('/explore'), child: const Text('Explore products')),
                ],
              ),
            );
          }

          final user = AppConfig.isSupabaseConfigured ? Supabase.instance.client.auth.currentUser : null;
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AlteoColors.mint, borderRadius: BorderRadius.circular(18)),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: AlteoColors.forest),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Preview checkout only. No order or payment will be created from this build.',
                        style: TextStyle(color: AlteoColors.forestDeep, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('Order summary', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...cart.lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(line.product.name + ' × ' + line.quantity.toString())),
                      Text('₹' + line.lineTotalRupees.toString()),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Preview subtotal', style: Theme.of(context).textTheme.titleMedium)),
                  Text('₹' + cart.subtotalRupees.toString(), style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 20),
              Text('Before real checkout is enabled', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              const _RequirementRow(text: 'Reviewed order, address and inventory database policies'),
              const _RequirementRow(text: 'Server-side price, fees, tax and promotion calculation'),
              const _RequirementRow(text: 'Payment provider, verified webhooks and refund handling'),
              const _RequirementRow(text: 'Idempotent order placement and fulfilment integration'),
              const SizedBox(height: 20),
              if (user == null)
                FilledButton.icon(
                  onPressed: AppConfig.isSupabaseConfigured
                      ? () => AuthService.signIn(context)
                      : () => AuthService.showConfigurationMessage(context),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Continue with Google'),
                )
              else
                const FilledButton(
                  onPressed: null,
                  child: Text('Real checkout is not enabled yet'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.go('/cart'),
                child: const Text('Return to cart'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: AlteoColors.forest, size: 19),
          const SizedBox(width: 9),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
