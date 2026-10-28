import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerBanner {
  const CustomerBanner(this.title, this.subtitle, this.imageUrl, this.actionType, this.actionValue);
  final String title, subtitle, imageUrl, actionType, actionValue;
  factory CustomerBanner.fromMap(Map<String, dynamic> m) => CustomerBanner((m['title'] as String?) ?? '', (m['subtitle'] as String?) ?? '', (m['image_url'] as String?) ?? '', (m['action_type'] as String?) ?? 'none', (m['action_value'] as String?) ?? '');
}

class CustomerProduct {
  const CustomerProduct(this.id, this.name, this.description, this.priceMinor, this.imageUrl, this.kind);
  final String id, name, description, imageUrl, kind;
  final int priceMinor;
  String get priceLabel => '₹${(priceMinor / 100).toStringAsFixed(0)}';
  factory CustomerProduct.fromMap(Map<String, dynamic> m) => CustomerProduct(m['id'] as String, (m['name'] as String?) ?? 'Item', (m['description'] as String?) ?? '', (m['price_minor'] as num?)?.toInt() ?? 0, (m['image_url'] as String?) ?? '', (m['kind'] as String?) ?? 'shopping');
}

class CustomerContentService {
  CustomerContentService(this.client);
  final SupabaseClient client;

  Future<List<CustomerBanner>> loadBanners() async {
    final rows = await client.from('app_banners').select('title,subtitle,image_url,priority,action_type,action_value').eq('active', true).order('priority').limit(8);
    return (rows as List).map((e) => CustomerBanner.fromMap(Map<String,dynamic>.from(e as Map))).toList();
  }

  Future<Map<String, dynamic>> getPublicServiceability(String pincode) async {
    final pin = pincode.trim();
    if (!RegExp(r'^[1-9][0-9]{5}

  /// Returns quantities currently held by the signed-in user's active cart.
  Future<Map<String, int>> loadCartQuantities() async {
    final user = client.auth.currentUser;
    if (user == null) return <String, int>{};
    final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    if (cart == null) return <String, int>{};
    final rows = await client.from('cart_items').select('product_id,quantity').eq('cart_id', cart['id']);
    return <String, int>{
      for (final row in (rows as List).map((e) => Map<String, dynamic>.from(e as Map)))
        row['product_id'].toString(): (row['quantity'] as num?)?.toInt() ?? 0,
    };
  }

  /// Sets exact quantity from a +/- control. Quantity zero removes the item.
  Future<void> setCartQuantity(String productId, int quantity) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before adding items to your cart.');
    if (quantity < 0) throw ArgumentError.value(quantity, 'quantity', 'Must not be negative.');

    var cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    if (cart == null && quantity == 0) return;
    if (cart == null) {
      cart = await client.from('carts').insert({'customer_id': user.id, 'status': 'active'}).select('id').single();
    }
    final cartId = cart['id'] as String;
    final existingItem = await client.from('cart_items').select('id').eq('cart_id', cartId).eq('product_id', productId).maybeSingle();

    if (quantity == 0) {
      if (existingItem != null) await client.from('cart_items').delete().eq('id', existingItem['id']);
      return;
    }

    if (existingItem == null) {
      await client.from('cart_items').insert({'cart_id': cartId, 'product_id': productId, 'quantity': quantity});
    } else {
      await client.from('cart_items').update({'quantity': quantity}).eq('id', existingItem['id']);
    }
  }

  Future<void> addToCart(String productId) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before adding items to your cart.');
    final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    final cartId = cart == null
        ? (await client.from('carts').insert({'customer_id': user.id, 'status': 'active'}).select('id').single())['id'] as String
        : cart['id'] as String;
    final existingItem = await client.from('cart_items').select('id,quantity').eq('cart_id', cartId).eq('product_id', productId).maybeSingle();
    if (existingItem == null) {
      await client.from('cart_items').insert({'cart_id': cartId, 'product_id': productId, 'quantity': 1});
    } else {
      await client.from('cart_items').update({'quantity': ((existingItem['quantity'] as num).toInt()) + 1}).eq('id', existingItem['id']);
    }
  }
}
).hasMatch(pin)) {
      return <String, dynamic>{
        'serviceable': false,
        'pincode': pin,
        'message': 'Enter a valid 6-digit PIN code.',
      };
    }
    final response = await client.rpc(
      'get_public_serviceability',
      params: <String, dynamic>{'p_pincode': pin},
    ).timeout(const Duration(seconds: 12));
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<CustomerProduct>> loadProducts({String? kind, String? pincode}) async {
    final pin = pincode?.trim() ?? '';
    if (!RegExp(r'^[1-9][0-9]{5}

  /// Returns quantities currently held by the signed-in user's active cart.
  Future<Map<String, int>> loadCartQuantities() async {
    final user = client.auth.currentUser;
    if (user == null) return <String, int>{};
    final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    if (cart == null) return <String, int>{};
    final rows = await client.from('cart_items').select('product_id,quantity').eq('cart_id', cart['id']);
    return <String, int>{
      for (final row in (rows as List).map((e) => Map<String, dynamic>.from(e as Map)))
        row['product_id'].toString(): (row['quantity'] as num?)?.toInt() ?? 0,
    };
  }

  /// Sets exact quantity from a +/- control. Quantity zero removes the item.
  Future<void> setCartQuantity(String productId, int quantity) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before adding items to your cart.');
    if (quantity < 0) throw ArgumentError.value(quantity, 'quantity', 'Must not be negative.');

    var cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    if (cart == null && quantity == 0) return;
    if (cart == null) {
      cart = await client.from('carts').insert({'customer_id': user.id, 'status': 'active'}).select('id').single();
    }
    final cartId = cart['id'] as String;
    final existingItem = await client.from('cart_items').select('id').eq('cart_id', cartId).eq('product_id', productId).maybeSingle();

    if (quantity == 0) {
      if (existingItem != null) await client.from('cart_items').delete().eq('id', existingItem['id']);
      return;
    }

    if (existingItem == null) {
      await client.from('cart_items').insert({'cart_id': cartId, 'product_id': productId, 'quantity': quantity});
    } else {
      await client.from('cart_items').update({'quantity': quantity}).eq('id', existingItem['id']);
    }
  }

  Future<void> addToCart(String productId) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before adding items to your cart.');
    final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    final cartId = cart == null
        ? (await client.from('carts').insert({'customer_id': user.id, 'status': 'active'}).select('id').single())['id'] as String
        : cart['id'] as String;
    final existingItem = await client.from('cart_items').select('id,quantity').eq('cart_id', cartId).eq('product_id', productId).maybeSingle();
    if (existingItem == null) {
      await client.from('cart_items').insert({'cart_id': cartId, 'product_id': productId, 'quantity': 1});
    } else {
      await client.from('cart_items').update({'quantity': ((existingItem['quantity'] as num).toInt()) + 1}).eq('id', existingItem['id']);
    }
  }
}
).hasMatch(pin)) return <CustomerProduct>[];
    final area = await getPublicServiceability(pin);
    if (area['serviceable'] != true) return <CustomerProduct>[];

    var q = client.from('seller_products')
        .select('id,name,description,price_minor,image_url,kind')
        .eq('status', 'active')
        .not('image_url', 'is', null)
        .neq('image_url', '');
    if (kind != null) q = q.eq('kind', kind);
    final rows = await q.order('created_at', ascending: false).limit(30);
    return (rows as List)
        .map((e) => CustomerProduct.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((product) => product.imageUrl.startsWith('https://'))
        .toList();
  }

  Future<List<CustomerProduct>> searchProducts({required String query, String? pincode}) async {
    final pin = pincode?.trim() ?? '';
    if (!RegExp(r'^[1-9][0-9]{5}

  /// Returns quantities currently held by the signed-in user's active cart.
  Future<Map<String, int>> loadCartQuantities() async {
    final user = client.auth.currentUser;
    if (user == null) return <String, int>{};
    final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    if (cart == null) return <String, int>{};
    final rows = await client.from('cart_items').select('product_id,quantity').eq('cart_id', cart['id']);
    return <String, int>{
      for (final row in (rows as List).map((e) => Map<String, dynamic>.from(e as Map)))
        row['product_id'].toString(): (row['quantity'] as num?)?.toInt() ?? 0,
    };
  }

  /// Sets exact quantity from a +/- control. Quantity zero removes the item.
  Future<void> setCartQuantity(String productId, int quantity) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before adding items to your cart.');
    if (quantity < 0) throw ArgumentError.value(quantity, 'quantity', 'Must not be negative.');

    var cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    if (cart == null && quantity == 0) return;
    if (cart == null) {
      cart = await client.from('carts').insert({'customer_id': user.id, 'status': 'active'}).select('id').single();
    }
    final cartId = cart['id'] as String;
    final existingItem = await client.from('cart_items').select('id').eq('cart_id', cartId).eq('product_id', productId).maybeSingle();

    if (quantity == 0) {
      if (existingItem != null) await client.from('cart_items').delete().eq('id', existingItem['id']);
      return;
    }

    if (existingItem == null) {
      await client.from('cart_items').insert({'cart_id': cartId, 'product_id': productId, 'quantity': quantity});
    } else {
      await client.from('cart_items').update({'quantity': quantity}).eq('id', existingItem['id']);
    }
  }

  Future<void> addToCart(String productId) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before adding items to your cart.');
    final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    final cartId = cart == null
        ? (await client.from('carts').insert({'customer_id': user.id, 'status': 'active'}).select('id').single())['id'] as String
        : cart['id'] as String;
    final existingItem = await client.from('cart_items').select('id,quantity').eq('cart_id', cartId).eq('product_id', productId).maybeSingle();
    if (existingItem == null) {
      await client.from('cart_items').insert({'cart_id': cartId, 'product_id': productId, 'quantity': 1});
    } else {
      await client.from('cart_items').update({'quantity': ((existingItem['quantity'] as num).toInt()) + 1}).eq('id', existingItem['id']);
    }
  }
}
).hasMatch(pin)) return <CustomerProduct>[];
    final area = await getPublicServiceability(pin);
    if (area['serviceable'] != true) return <CustomerProduct>[];
    final rows = await client.from('seller_products')
        .select('id,name,description,price_minor,image_url,kind')
        .eq('status', 'active')
        .not('image_url', 'is', null)
        .neq('image_url', '')
        .ilike('name', '%${query.trim()}%')
        .order('created_at', ascending: false)
        .limit(30);
    return (rows as List)
        .map((e) => CustomerProduct.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((product) => product.imageUrl.startsWith('https://'))
        .toList();
  }

  /// Returns quantities currently held by the signed-in user's active cart.
  Future<Map<String, int>> loadCartQuantities() async {
    final user = client.auth.currentUser;
    if (user == null) return <String, int>{};
    final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    if (cart == null) return <String, int>{};
    final rows = await client.from('cart_items').select('product_id,quantity').eq('cart_id', cart['id']);
    return <String, int>{
      for (final row in (rows as List).map((e) => Map<String, dynamic>.from(e as Map)))
        row['product_id'].toString(): (row['quantity'] as num?)?.toInt() ?? 0,
    };
  }

  /// Sets exact quantity from a +/- control. Quantity zero removes the item.
  Future<void> setCartQuantity(String productId, int quantity) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before adding items to your cart.');
    if (quantity < 0) throw ArgumentError.value(quantity, 'quantity', 'Must not be negative.');

    var cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    if (cart == null && quantity == 0) return;
    if (cart == null) {
      cart = await client.from('carts').insert({'customer_id': user.id, 'status': 'active'}).select('id').single();
    }
    final cartId = cart['id'] as String;
    final existingItem = await client.from('cart_items').select('id').eq('cart_id', cartId).eq('product_id', productId).maybeSingle();

    if (quantity == 0) {
      if (existingItem != null) await client.from('cart_items').delete().eq('id', existingItem['id']);
      return;
    }

    if (existingItem == null) {
      await client.from('cart_items').insert({'cart_id': cartId, 'product_id': productId, 'quantity': quantity});
    } else {
      await client.from('cart_items').update({'quantity': quantity}).eq('id', existingItem['id']);
    }
  }

  Future<void> addToCart(String productId) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before adding items to your cart.');
    final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
    final cartId = cart == null
        ? (await client.from('carts').insert({'customer_id': user.id, 'status': 'active'}).select('id').single())['id'] as String
        : cart['id'] as String;
    final existingItem = await client.from('cart_items').select('id,quantity').eq('cart_id', cartId).eq('product_id', productId).maybeSingle();
    if (existingItem == null) {
      await client.from('cart_items').insert({'cart_id': cartId, 'product_id': productId, 'quantity': 1});
    } else {
      await client.from('cart_items').update({'quantity': ((existingItem['quantity'] as num).toInt()) + 1}).eq('id', existingItem['id']);
    }
  }
}
