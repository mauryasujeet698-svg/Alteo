import 'package:customer/core/widgets/catalogue_preview_notice.dart';
import 'package:customer/core/widgets/section_heading.dart';
import 'package:customer/features/catalog/data/preview_products.dart';
import 'package:customer/features/catalog/presentation/product_card.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';

  static const _categories = <String>['All', 'Fruit', 'Vegetables', 'Dairy', 'Pantry', 'Snacks'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartStoreProvider);
    final query = _searchController.text.trim().toLowerCase();
    final products = PreviewProducts.all.where((product) {
      final matchesQuery = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
      final matchesCategory = _selectedCategory == 'All' || product.category == _selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('Explore', style: Theme.of(context).textTheme.headlineMedium),
        actions: [
          IconButton(
            tooltip: 'Open cart',
            onPressed: () => context.go('/cart'),
            icon: cart.itemCount == 0
                ? const Icon(Icons.shopping_bag_outlined)
                : Badge(label: Text(cart.itemCount.toString()), child: const Icon(Icons.shopping_bag_outlined)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, child) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Find your everyday favourites', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search products and categories',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const CataloguePreviewNotice(),
                    const SizedBox(height: 22),
                    const SectionHeading(title: 'Browse categories'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          return ChoiceChip(
                            label: Text(category),
                            selected: _selectedCategory == category,
                            onSelected: (_) => setState(() => _selectedCategory = category),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                    SectionHeading(title: _selectedCategory == 'All' ? 'Popular right now' : _selectedCategory),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off_rounded, size: 42),
                        const SizedBox(height: 10),
                        Text('Nothing found', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 5),
                        const Text('Try another search or category.'),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = width > 900 ? 4 : width > 600 ? 3 : 2;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 280,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = products[index];
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
                        childCount: products.length,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
