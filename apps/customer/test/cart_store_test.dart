import 'package:customer/features/cart/cart_store.dart';
import 'package:customer/features/catalog/data/preview_products.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CartStore preview cart', () {
    late CartStore cart;

    setUp(() {
      cart = CartStore();
    });

    tearDown(() {
      cart.dispose();
    });

    test('adding a product creates a line and updates subtotal', () {
      final product = PreviewProducts.all.first;
      cart.add(product);
      expect(cart.itemCount, 1);
      expect(cart.lines, hasLength(1));
      expect(cart.subtotalRupees, product.priceRupees);
    });

    test('adding the same product increments quantity instead of duplicating lines', () {
      final product = PreviewProducts.all.first;
      cart.add(product);
      cart.add(product);
      expect(cart.lines, hasLength(1));
      expect(cart.itemCount, 2);
      expect(cart.subtotalRupees, product.priceRupees * 2);
    });

    test('decrementing the last unit removes the line', () {
      final product = PreviewProducts.all.first;
      cart.add(product);
      cart.decrement(product.id);
      expect(cart.isEmpty, isTrue);
      expect(cart.subtotalRupees, 0);
    });

    test('clear resets all cart lines', () {
      cart.add(PreviewProducts.all[0]);
      cart.add(PreviewProducts.all[1]);
      cart.clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.itemCount, 0);
      expect(cart.subtotalRupees, 0);
    });
  });
}
