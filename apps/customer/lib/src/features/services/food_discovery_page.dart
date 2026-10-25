import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';
import '../../services/customer_content_service.dart';
import '../../services/mapbox_service.dart';

class FoodDiscoveryPage extends StatefulWidget {
  const FoodDiscoveryPage({super.key, this.enableBackendQueries = true});
  final bool enableBackendQueries;
  @override
  State<FoodDiscoveryPage> createState() => _FoodDiscoveryPageState();
}

class _FoodDiscoveryPageState extends State<FoodDiscoveryPage> {
  final TextEditingController searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> foodFuture;
  String category = 'All';
  String deliveryLocation = 'Choose your delivery location';
  bool locating = false;

  @override
  void initState() { super.initState(); foodFuture = _loadFood(); }
  @override
  void dispose() { searchController.dispose(); super.dispose(); }

  Future<List<Map<String, dynamic>>> _loadFood() async {
    if (!widget.enableBackendQueries) return <Map<String, dynamic>>[];
    final client = Supabase.instance.client;
    final raw = await client.from('seller_products')
        .select('id,name,description,price_minor,image_url,seller_id')
        .eq('status', 'active').eq('kind', 'food')
        .order('created_at', ascending: false).limit(40);
    final products = (raw as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    if (products.isEmpty) return products;
    final sellerIds = products.map((p) => p['seller_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty).toSet().toList();
    final sellerNames = <String, String>{};
    if (sellerIds.isNotEmpty) {
      try {
        final sellers = await client.from('sellers').select('id,display_name').inFilter('id', sellerIds);
        for (final row in sellers as List) {
          final seller = Map<String, dynamic>.from(row as Map);
          sellerNames[seller['id'].toString()] = seller['display_name']?.toString() ?? 'Local kitchen';
        }
      } catch (_) {}
    }
    return products.map((p) => <String, dynamic>{
      ...p, 'seller_name': sellerNames[p['seller_id']?.toString()] ?? 'Alteo food partner',
    }).toList();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message('Turn on Location on your phone and try again.'); return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _message('Allow location access to set your delivery area, or continue browsing.'); return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final address = await MapboxService.reverseGeocode(position.longitude, position.latitude);
      if (!mounted) return;
      setState(() => deliveryLocation = address ?? 'Current location selected');
      if (address == null) _message('Location selected. Add a Mapbox public token to show a readable address.');
    } catch (_) {
      _message('Could not detect your location. You can continue browsing and choose it later.');
    } finally { if (mounted) setState(() => locating = false); }
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
      if (!mounted || client.auth.currentUser == null) return;
    }
    try {
      await CustomerContentService(client).addToCart(product['id'].toString());
      _message((product['name']?.toString() ?? 'Item') + ' added to your cart.');
    } catch (e) { _message('Could not add this item. Check your account and cart settings. ' + e.toString()); }
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> items) {
    final query = searchController.text.trim().toLowerCase();
    return items.where((p) {
      final text = (p['name']?.toString() ?? '') + ' ' +
          (p['description']?.toString() ?? '') + ' ' + (p['seller_name']?.toString() ?? '');
      final lower = text.toLowerCase();
      final matchesQuery = query.isEmpty || lower.contains(query);
      final matchesCategory = category == 'All' || lower.contains(category.toLowerCase()) ||
          (category == 'Snacks' && (lower.contains('drink') || lower.contains('chat')));
      return matchesQuery && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Food & restaurants', style: TextStyle(fontWeight: FontWeight.w900)),
      actions: [IconButton(tooltip: 'Refresh food listings', onPressed: () => setState(() => foodFuture = _loadFood()), icon: const Icon(Icons.refresh_rounded))],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: foodFuture,
      builder: (context, snapshot) {
        final allItems = snapshot.data ?? const <Map<String, dynamic>>[];
        final items = _filtered(allItems);
        final restaurantNames = allItems.map((p) => p['seller_name']?.toString() ?? 'Food partner').toSet().toList();
        return RefreshIndicator(
          onRefresh: () async { setState(() => foodFuture = _loadFood()); await foodFuture; },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              InkWell(
                onTap: _useCurrentLocation,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE3E9E5))),
                  child: Row(children: [
                    const Icon(Icons.location_on_outlined, color: Color(0xFF176B57)),
                    const SizedBox(width: 9),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('DELIVERING TO', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800, color: Color(0xFF68736D))),
                      const SizedBox(height: 3),
                      Text(deliveryLocation, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ])),
                    if (locating) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else const Icon(Icons.keyboard_arrow_down_rounded),
                  ]),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: searchController, onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search dishes, restaurants and cuisines',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: searchController.text.isEmpty ? const Icon(Icons.tune_rounded) : IconButton(onPressed: () => setState(() => searchController.clear()), icon: const Icon(Icons.close_rounded)),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFE3E9E5))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFE3E9E5))),
                ),
              ),
              const SizedBox(height: 17),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF3C9875)]), borderRadius: BorderRadius.circular(23)),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SOMETHING DELICIOUS AWAITS', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
                  SizedBox(height: 8),
                  Text('Good food, closer to home.', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.08)),
                  SizedBox(height: 7),
                  Text('Explore dishes and menus from approved Alteo food partners.', style: TextStyle(color: Colors.white, height: 1.4)),
                ]),
              ),
              const SizedBox(height: 22),
              const Text('Explore by craving', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              SizedBox(height: 98, child: ListView(scrollDirection: Axis.horizontal, children: [
                _category('Biryani', Icons.rice_bowl_rounded, const Color(0xFFFFE7D7)),
                _category('Pizza', Icons.local_pizza_rounded, const Color(0xFFFFE2E2)),
                _category('Thali', Icons.dinner_dining_rounded, const Color(0xFFFFF0C7)),
                _category('Snacks', Icons.local_cafe_rounded, const Color(0xFFE8E3FF)),
                _category('Meals', Icons.restaurant_rounded, const Color(0xFFDFF2E7)),
              ])),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: Text('Restaurants to explore', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                Text(restaurantNames.length.toString() + ' available', style: const TextStyle(color: Color(0xFF68736D), fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                _emptyPanel('Food listings are temporarily unavailable', 'Check your connection and public catalogue permissions, then refresh.')
              else if (restaurantNames.isEmpty)
                _emptyPanel('More local menus are coming', 'Approved food partners and active menu items will appear here automatically.')
              else
                SizedBox(height: 102, child: ListView(scrollDirection: Axis.horizontal, children: restaurantNames.take(12).map((name) => Container(
                  width: 145, margin: const EdgeInsets.only(right: 10), padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3E9E5))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.storefront_rounded, size: 27, color: Color(0xFF176B57)),
                    const Spacer(),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Text('Menu on Alteo', style: TextStyle(fontSize: 11, color: Color(0xFF68736D))),
                  ]),
                )).toList())),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: Text('Popular food items', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                Text(items.length.toString() + ' items', style: const TextStyle(color: Color(0xFF68736D), fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              SizedBox(height: 37, child: ListView(scrollDirection: Axis.horizontal, children: [
                _filter('All'), _filter('Biryani'), _filter('Pizza'), _filter('Thali'), _filter('Snacks'), _filter('Meals'),
              ])),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                _emptyPanel('Unable to load the menu', 'Pull down to try again.')
              else if (items.isEmpty)
                _emptyPanel('No matching dishes yet', 'Try another search or category. New menu items appear after sellers publish them and admin approves them.')
              else
                GridView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .63),
                  itemBuilder: (context, index) => _foodCard(items[index]),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _category(String label, IconData icon, Color color) => InkWell(
    onTap: () => setState(() => category = label),
    borderRadius: BorderRadius.circular(15),
    child: Container(width: 76, margin: const EdgeInsets.only(right: 10), child: Column(children: [
      Container(height: 61, width: 61, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)), child: Icon(icon, color: const Color(0xFF176B57), size: 29)),
      const SizedBox(height: 7), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ])),
  );

  Widget _filter(String value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(label: Text(value), selected: category == value, onSelected: (_) => setState(() => category = value), selectedColor: const Color(0xFFCCEBDD)),
  );

  Widget _foodCard(Map<String, dynamic> product) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE3E9E5))),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 5, child: Stack(fit: StackFit.expand, children: [
        if ((product['image_url']?.toString() ?? '').startsWith('https://'))
          Image.network(product['image_url'].toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _foodImagePlaceholder())
        else _foodImagePlaceholder(),
        Positioned(right: 8, top: 8, child: Container(decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94), borderRadius: BorderRadius.circular(9)), padding: const EdgeInsets.all(5), child: const Icon(Icons.restaurant_menu_rounded, size: 17, color: Color(0xFF176B57)))),
      ])),
      Expanded(flex: 5, child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(product['name']?.toString() ?? 'Menu item', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.15)),
          const SizedBox(height: 4),
          Text(product['seller_name']?.toString() ?? 'Alteo food partner', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF68736D))),
          const Spacer(),
          Row(children: [
            Expanded(child: Text('₹' + (((product['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
            IconButton(tooltip: 'Add to cart', onPressed: () => _addToCart(product), icon: const Icon(Icons.add_circle_rounded, color: Color(0xFF176B57), size: 29), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 32)),
          ]),
        ]),
      )),
    ]),
  );

  Widget _foodImagePlaceholder() => Container(color: const Color(0xFFE7F3EC), child: const Center(child: Icon(Icons.ramen_dining_rounded, size: 45, color: Color(0xFF176B57))));

  Widget _emptyPanel(String title, String body) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE3E9E5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 5), Text(body, style: const TextStyle(color: Color(0xFF68736D), height: 1.45)),
    ]),
  );
}
