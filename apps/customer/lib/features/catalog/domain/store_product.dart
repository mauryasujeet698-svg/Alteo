class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.priceRupees,
    required this.mrpRupees,
    required this.imageUrl,
    required this.description,
    this.rating = 4.6,
  });

  final String id;
  final String name;
  final String category;
  final String unit;
  final int priceRupees;
  final int mrpRupees;
  final String imageUrl;
  final String description;
  final double rating;

  int get discountPercent {
    if (mrpRupees <= priceRupees || mrpRupees == 0) return 0;
    return (((mrpRupees - priceRupees) / mrpRupees) * 100).round();
  }
}
