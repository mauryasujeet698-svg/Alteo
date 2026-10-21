import 'package:cached_network_image/cached_network_image.dart';
import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/core/widgets/catalogue_preview_notice.dart';
import 'package:customer/core/widgets/section_heading.dart';
import 'package:customer/features/catalog/data/preview_products.dart';
import 'package:customer/features/location/location_picker_sheet.dart';
import 'package:customer/features/catalog/presentation/product_card.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartStoreProvider);
    final location = ref.watch(locationStoreProvider).label;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, child) {
        return Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              height: 42,
                              width: 42,
                              decoration: BoxDecoration(
                                color: AlteoColors.forest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'a.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('alteo', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 21, letterSpacing: -0.5)),
                                  Text('Good things, closer.', style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Open cart',
                              onPressed: () => context.go('/cart'),
                              icon: cart.itemCount == 0
                                  ? const Icon(Icons.shopping_bag_outlined)
                                  : Badge(
                                      label: Text(cart.itemCount.toString()),
                                      child: const Icon(Icons.shopping_bag_outlined),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 17),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (context) => const LocationPickerSheet(),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined, color: AlteoColors.forest, size: 21),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('DELIVER TO', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 2),
                                    Text(location, style: Theme.of(context).textTheme.titleMedium),
                                  ],
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down_rounded),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        InkWell(
                          onTap: () => context.go('/explore'),
                          borderRadius: BorderRadius.circular(16),
                          child: IgnorePointer(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Search products, food and services',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: Icon(Icons.mic_none_rounded, color: Theme.of(context).colorScheme.primary),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const CataloguePreviewNotice(),
                        const SizedBox(height: 18),
                        _HeroBanner(onExplore: () => context.go('/explore')),
                        const SizedBox(height: 24),
                        Text('What do you need today?', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            Expanded(child: _ServiceShortcut(icon: Icons.shopping_basket_outlined, label: 'Shop', tint: const Color(0xFFE5F3EA), onTap: () => context.go('/service/shop'))),
                            const SizedBox(width: 8),
                            Expanded(child: _ServiceShortcut(icon: Icons.restaurant_outlined, label: 'Food', tint: const Color(0xFFFFE7DE), onTap: () => context.go('/service/food'))),
                            const SizedBox(width: 8),
                            Expanded(child: _ServiceShortcut(icon: Icons.bolt_rounded, label: 'Quick', tint: const Color(0xFFFFF0C9), onTap: () => context.go('/service/quick'))),
                            const SizedBox(width: 8),
                            Expanded(child: _ServiceShortcut(icon: Icons.directions_car_outlined, label: 'Rides', tint: const Color(0xFFE5EBFF), onTap: () => context.go('/service/rides'))),
                            const SizedBox(width: 8),
                            Expanded(child: _ServiceShortcut(icon: Icons.local_shipping_outlined, label: 'Parcel', tint: const Color(0xFFECE5FA), onTap: () => context.go('/service/parcel'))),
                          ],
                        ),
                        const SizedBox(height: 26),
                        SectionHeading(
                          title: 'Daily essentials',
                          actionLabel: 'See all',
                          onAction: () => context.go('/explore'),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 274,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: PreviewProducts.all.length,
                            separatorBuilder: (context, index) => const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final product = PreviewProducts.all[index];
                              return ProductCard(
                                product: product,
                                onTap: () => context.push('/product/' + product.id),
                                onAdd: () {
                                  cart.add(product);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(product.name + ' added to your preview cart'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: AlteoColors.mint, borderRadius: BorderRadius.circular(14)),
                                child: const Icon(Icons.favorite_border_rounded, color: AlteoColors.forest),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Your kind of convenient', style: Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 4),
                                    Text('One place for the everyday things that keep life moving.', style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
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
      },
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 194,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: 'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=1200&q=85',
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(color: AlteoColors.forestDeep),
              placeholder: (context, url) => Container(color: AlteoColors.forestDeep),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xF20B3D2E),
                    Color(0xC90B3D2E),
                    Color(0x220B3D2E),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'THE EVERYDAY, ELEVATED',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Your everyday,\nall in one place.',
                    style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.08, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 38,
                    child: FilledButton(
                      onPressed: onExplore,
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AlteoColors.forestDeep, minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      child: const Text('Explore Alteo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceShortcut extends StatelessWidget {
  const _ServiceShortcut({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(17)),
              alignment: Alignment.center,
              child: Icon(icon, size: 25, color: AlteoColors.forestDeep),
            ),
          ),
          const SizedBox(height: 7),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
