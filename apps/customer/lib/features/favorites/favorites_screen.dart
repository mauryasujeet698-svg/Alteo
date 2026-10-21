import 'package:customer/core/widgets/catalogue_preview_notice.dart';
import 'package:customer/features/cart/cart_store.dart';
import 'package:customer/features/catalog/data/preview_products.dart';
import 'package:customer/features/catalog/presentation/product_card.dart';
import 'package:customer/features/favorites/favorite_store.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteStoreProvider);
    final cart = ref.watch(cartStoreProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Your favourites', style: Theme.of(context).textTheme.headlineMedium)),
      body: ListenableBuilder(
        listenable: Listenable.merge([favorites, cart]),
        builder: (context, child) {
          final products = PreviewProducts.all.where((p) => favorites.contains(p.id)).toList(growable: false);
          if (products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_border_rounded, size: 44),
                    const SizedBox(height: 14),
                    Text('Keep the good ones close', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text('Tap the heart on a product to save it here. Guest favourites stay on this device until connected to your account.', textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    const CataloguePreviewNotice(),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => context.go('/explore'), child: const Text('Explore products')),
                  ],
                ),
              ),
            );
          }
          return CustomScrollView(slivers: [
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(18, 12, 18, 16), child: CataloguePreviewNotice())),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 280,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final product = products[index];
                    return ProductCard(
                      product: product,
                      onTap: () => context.push('/product/' + product.id),
                      onAdd: () => cart.add(product),
                    );
                  },
                  childCount: products.length,
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
