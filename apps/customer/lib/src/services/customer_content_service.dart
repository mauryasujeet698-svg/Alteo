import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerBanner {
  const CustomerBanner(this.title, this.subtitle, this.imageUrl);
  final String title, subtitle, imageUrl;
  factory CustomerBanner.fromMap(Map<String, dynamic> m) => CustomerBanner((m['title'] as String?) ?? '', (m['subtitle'] as String?) ?? '', (m['image_url'] as String?) ?? '');
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
    final rows = await client.from('app_banners').select('title,subtitle,image_url,priority').eq('active', true).order('priority').limit(8);
    return (rows as List).map((e) => CustomerBanner.fromMap(Map<String,dynamic>.from(e as Map))).toList();
  }
  Future<List<CustomerProduct>> loadProducts({String? kind}) async {
    var q = client.from('seller_products').select('id,name,description,price_minor,image_url,kind').eq('status','active');
    if (kind != null) q = q.eq('kind', kind);
    final rows = await q.order('created_at', ascending: false).limit(20);
    return (rows as List).map((e) => CustomerProduct.fromMap(Map<String,dynamic>.from(e as Map))).toList();
  }
}