import 'package:customer/features/catalog/domain/store_product.dart';
import 'package:flutter/foundation.dart';

class CartLine {
  CartLine({required this.product, this.quantity = 1});

  final StoreProduct product;
  int quantity;

  int get lineTotalRupees => product.priceRupees * quantity;
}

/// Local-only preview cart. The backend must validate final price and inventory.
class CartStore extends ChangeNotifier {
  final Map<String, CartLine> _lines = <String, CartLine>{};

  List<CartLine> get lines => List<CartLine>.unmodifiable(_lines.values);
  bool get isEmpty => _lines.isEmpty;
  int get itemCount =>
      _lines.values.fold<int>(0, (sum, line) => sum + line.quantity);
  int get subtotalRupees => _lines.values.fold<int>(
        0,
        (sum, line) => sum + line.lineTotalRupees,
      );

  void add(StoreProduct product) {
    final existing = _lines[product.id];
    if (existing == null) {
      _lines[product.id] = CartLine(product: product);
    } else {
      existing.quantity += 1;
    }
    notifyListeners();
  }

  void increment(String productId) {
    final line = _lines[productId];
    if (line == null) return;
    line.quantity += 1;
    notifyListeners();
  }

  void decrement(String productId) {
    final line = _lines[productId];
    if (line == null) return;
    if (line.quantity <= 1) {
      _lines.remove(productId);
    } else {
      line.quantity -= 1;
    }
    notifyListeners();
  }

  void remove(String productId) {
    if (_lines.remove(productId) != null) notifyListeners();
  }

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
  }
}
