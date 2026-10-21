import 'package:cached_network_image/cached_network_image.dart';
import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/features/catalog/data/preview_products.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matching = PreviewProducts.all.where((item) => item.id == productId);
    if (matching.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This preview item could not be found.')),
      );
    }
    final product = matching.first;
    final cart = ref.watch(cartStoreProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product details'),
        actions: [
          IconButton(
            tooltip: 'Open cart',
            onPressed: () => context.go('/cart'),
            icon: cart.itemCount == 0
                ? const Icon(Icons.shopping_bag_outlined)
                : Badge(label: Text(cart.itemCount.toString()), child: const Icon(Icons.shopping_bag_outlined)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, child) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AspectRatio(
                      aspectRatio: 1.08,
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: AlteoColors.mint, child: const Icon(Icons.eco_outlined, size: 48)),
                        errorWidget: (context, url, error) => Container(color: AlteoColors.mint, child: const Icon(Icons.local_grocery_store_outlined, size: 48)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Text(product.name, style: Theme.of(context).textTheme.headlineMedium)),
                      if (product.discountPercent > 0)
                        Chip(
                          label: Text(product.discountPercent.toString() + '% off'),
                          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(product.unit, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('₹' + product.priceRupees.toString(), style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(width: 10),
                      if (product.mrpRupees > product.priceRupees)
                        Text(
                          '₹' + product.mrpRupees.toString(),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough),
                        ),
                      const Spacer(),
                      const Icon(Icons.star_rounded, color: Color(0xFFF2B544), size: 20),
                      Text(product.rating.toStringAsFixed(1), style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('About this item', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(product.description),
                  const SizedBox(height: 18),
                  const Text('Preview only: final price, seller, stock and serviceability must be confirmed by the live Alteo backend before checkout.'),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/cart'),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: Text('Cart (' + cart.itemCount.toString() + ')'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          cart.add(product);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(product.name + ' added to your preview cart')),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add to cart'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
