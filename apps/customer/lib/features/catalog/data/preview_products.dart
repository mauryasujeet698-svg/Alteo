import 'package:customer/features/catalog/domain/store_product.dart';

/// Static preview records only; these are not live prices, stock levels, or offers.
abstract final class PreviewProducts {
  static const all = <StoreProduct>[
    StoreProduct(
      id: 'fruit-mango', name: 'Alphonso Mangoes', category: 'Fruit',
      unit: '2 pieces', priceRupees: 129, mrpRupees: 159,
      imageUrl: 'https://images.unsplash.com/photo-1553279768-865429fa0078?auto=format&fit=crop&w=700&q=80',
      description: 'Sweet, fragrant seasonal mangoes. Preview content; availability and price are not live.',
      rating: 4.8,
    ),
    StoreProduct(
      id: 'veg-tomato', name: 'Fresh Tomatoes', category: 'Vegetables',
      unit: '500 g', priceRupees: 28, mrpRupees: 35,
      imageUrl: 'https://images.unsplash.com/photo-1546094096-0df4bcaaa337?auto=format&fit=crop&w=700&q=80',
      description: 'Bright, ripe tomatoes for everyday cooking. Preview only; not available to order yet.',
      rating: 4.7,
    ),
    StoreProduct(
      id: 'dairy-milk', name: 'Farm Fresh Milk', category: 'Dairy',
      unit: '500 ml', priceRupees: 34, mrpRupees: 38,
      imageUrl: 'https://images.unsplash.com/photo-1563636619-e9143da7973b?auto=format&fit=crop&w=700&q=80',
      description: 'A sample dairy listing used to develop the customer experience.',
      rating: 4.6,
    ),
    StoreProduct(
      id: 'fruit-avocado', name: 'Avocados', category: 'Fruit',
      unit: '2 pieces', priceRupees: 99, mrpRupees: 119,
      imageUrl: 'https://images.unsplash.com/photo-1523049673857-eb18f1d7b578?auto=format&fit=crop&w=700&q=80',
      description: 'A sample fruit listing used to build and test browsing.',
      rating: 4.5,
    ),
    StoreProduct(
      id: 'veg-greens', name: 'Garden Greens', category: 'Vegetables',
      unit: '1 bunch', priceRupees: 32, mrpRupees: 40,
      imageUrl: 'https://images.unsplash.com/photo-1518843875459-f738682238a6?auto=format&fit=crop&w=700&q=80',
      description: 'A preview listing for the vegetable category.',
      rating: 4.4,
    ),
    StoreProduct(
      id: 'pantry-oats', name: 'Rolled Oats', category: 'Pantry',
      unit: '400 g', priceRupees: 89, mrpRupees: 109,
      imageUrl: 'https://images.unsplash.com/photo-1517673132405-a56a62b18caf?auto=format&fit=crop&w=700&q=80',
      description: 'A sample pantry listing. Pricing and availability need backend integration.',
      rating: 4.6,
    ),
    StoreProduct(
      id: 'snack-nuts', name: 'Mixed Nuts', category: 'Snacks',
      unit: '150 g', priceRupees: 149, mrpRupees: 179,
      imageUrl: 'https://images.unsplash.com/photo-1505576633757-0ac1084af824?auto=format&fit=crop&w=700&q=80',
      description: 'A sample snack listing for development.',
      rating: 4.7,
    ),
    StoreProduct(
      id: 'fruit-citrus', name: 'Sweet Oranges', category: 'Fruit',
      unit: '4 pieces', priceRupees: 69, mrpRupees: 79,
      imageUrl: 'https://images.unsplash.com/photo-1547514701-42782101795e?auto=format&fit=crop&w=700&q=80',
      description: 'A sample citrus listing used only in the preview catalogue.',
      rating: 4.6,
    ),
  ];
}
