import 'package:cached_network_image/cached_network_image.dart';
import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartStoreProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Your cart', style: Theme.of(context).textTheme.headlineMedium),
        actions: [
          if (!cart.isEmpty) TextButton(onPressed: cart.clear, child: const Text('Clear')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, child) {
          if (cart.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: const BoxDecoration(color: AlteoColors.mint, shape: BoxShape.circle),
                      child: const Icon(Icons.shopping_bag_outlined, size: 38, color: AlteoColors.forest),
                    ),
                    const SizedBox(height: 18),
                    Text('Your cart is taking a break', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    const Text('Explore the preview catalogue and add a few favourites.'),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: () => context.go('/explore'), child: const Text('Explore products')),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
                  itemCount: cart.lines.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final line = cart.lines[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 78,
                              height: 78,
                              child: CachedNetworkImage(
                                imageUrl: line.product.imageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(color: AlteoColors.mint),
                                errorWidget: (context, url, error) => Container(color: AlteoColors.mint, child: const Icon(Icons.eco_outlined)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.product.name, style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text(line.product.unit, style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 7),
                                Text('₹' + line.lineTotalRupees.toString(), style: Theme.of(context).textTheme.titleMedium),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).dividerColor),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(minWidth: 34, minHeight: 38),
                                  onPressed: () => cart.decrement(line.product.id),
                                  icon: const Icon(Icons.remove, size: 17),
                                ),
                                Text(line.quantity.toString(), style: Theme.of(context).textTheme.titleMedium),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(minWidth: 34, minHeight: 38),
                                  onPressed: () => cart.increment(line.product.id),
                                  icon: const Icon(Icons.add, size: 17),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Preview subtotal', style: Theme.of(context).textTheme.bodyMedium)),
                          Text('₹' + cart.subtotalRupees.toString(), style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Delivery fees, taxes and live stock are not included.', style: Theme.of(context).textTheme.bodySmall),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => context.push('/checkout'),
                          child: const Text('Continue to checkout'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
