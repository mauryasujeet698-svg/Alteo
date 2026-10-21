import 'dart:async';
import 'dart:convert';

import 'package:customer/features/catalog/data/preview_products.dart';
import 'package:customer/features/catalog/domain/store_product.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartLine {
  CartLine({required this.product, this.quantity = 1});

  final StoreProduct product;
  int quantity;

  int get lineTotalRupees => product.priceRupees * quantity;
}

/// Local-only guest preview cart. It persists product IDs and quantities for
/// convenience, never authoritative price, stock, checkout, or order data.
class CartStore extends ChangeNotifier {
  CartStore() {
    _hydrate();
  }

  static const _storageKey = 'alteo.guest_preview_cart.v1';
  final Map<String, CartLine> _lines = <String, CartLine>{};
  int _revision = 0;

  List<CartLine> get lines => List<CartLine>.unmodifiable(_lines.values);
  bool get isEmpty => _lines.isEmpty;
  int get itemCount =>
      _lines.values.fold<int>(0, (sum, line) => sum + line.quantity);
  int get subtotalRupees => _lines.values.fold<int>(
        0,
        (sum, line) => sum + line.lineTotalRupees,
      );

  Future<void> _hydrate() async {
    final startingRevision = _revision;
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      if (raw == null || _revision != startingRevision || _lines.isNotEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return;
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['id'];
        final quantity = item['quantity'];
        if (id is! String || quantity is! int || quantity < 1 || quantity > 99) {
          continue;
        }
        final matching = PreviewProducts.all.where((product) => product.id == id);
        if (matching.isNotEmpty) {
          _lines[id] = CartLine(product: matching.first, quantity: quantity);
        }
      }
      notifyListeners();
    } catch (_) {
      // Local storage may be unavailable in tests or on a device; use memory.
    }
  }

  void _persist() {
    unawaited(_write());
  }

  Future<void> _write() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final data = _lines.values
          .map((line) => <String, Object>{
                'id': line.product.id,
                'quantity': line.quantity,
              })
          .toList(growable: false);
      await preferences.setString(_storageKey, jsonEncode(data));
    } catch (_) {
      // The cart remains usable in memory if persistence fails.
    }
  }

  void add(StoreProduct product) {
    _revision++;
    final existing = _lines[product.id];
    if (existing == null) {
      _lines[product.id] = CartLine(product: product);
    } else if (existing.quantity < 99) {
      existing.quantity += 1;
    }
    notifyListeners();
    _persist();
  }

  void increment(String productId) {
    final line = _lines[productId];
    if (line == null || line.quantity >= 99) return;
    _revision++;
    line.quantity += 1;
    notifyListeners();
    _persist();
  }

  void decrement(String productId) {
    final line = _lines[productId];
    if (line == null) return;
    _revision++;
    if (line.quantity <= 1) {
      _lines.remove(productId);
    } else {
      line.quantity -= 1;
    }
    notifyListeners();
    _persist();
  }

  void remove(String productId) {
    if (_lines.remove(productId) == null) return;
    _revision++;
    notifyListeners();
    _persist();
  }

  void clear() {
    if (_lines.isEmpty) return;
    _revision++;
    _lines.clear();
    notifyListeners();
    _persist();
  }
}
