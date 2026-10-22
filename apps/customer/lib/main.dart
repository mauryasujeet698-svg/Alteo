import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/config/app_config.dart';
import 'src/features/services/service_browse_page.dart';
import 'src/features/search/customer_search_page.dart';
import 'src/features/location/customer_location_page.dart';
import 'src/features/orders/customer_orders_page.dart';
import 'src/features/account/customer_account_page.dart';
import 'src/services/mapbox_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

  if (config.supabaseUrl.isNotEmpty && config.supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
    );
  }
  MapboxService.configure(config.mapboxPublicToken);
  runApp(const AlteoCustomerApp());
}

class AlteoCustomerApp extends StatelessWidget {
  const AlteoCustomerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Alteo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF176B57),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F8F6),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF7F8F6),
            surfaceTintColor: Colors.transparent,
          ),
        ),
        home: const CustomerHomePage(),
      );
}

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedTab = 0;

  static const _services = <_ServiceItem>[
    _ServiceItem('Food', 'Meals & restaurants', Icons.restaurant_rounded, Color(0xFFFFE8D9), Color(0xFFB94E18)),
    _ServiceItem('Quick', 'Daily essentials', Icons.shopping_basket_rounded, Color(0xFFE3F4D8), Color(0xFF357A35)),
    _ServiceItem('Shop', 'Everyday shopping', Icons.shopping_bag_rounded, Color(0xFFE5E9FF), Color(0xFF4857B8)),
    _ServiceItem('Rides', 'Get there easily', Icons.directions_car_rounded, Color(0xFFFFF0C7), Color(0xFF8C6410)),
    _ServiceItem('Parcel', 'Send a package', Icons.local_shipping_rounded, Color(0xFFDDF3F1), Color(0xFF187B73)),
    _ServiceItem('More', 'Explore services', Icons.grid_view_rounded, Color(0xFFF0E4F7), Color(0xFF81519A)),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showComingSoon(String service) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$service is coming soon to Alteo.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildSearch()),
            SliverToBoxAdapter(child: _buildHeroBanner()),
            SliverToBoxAdapter(child: _buildSectionTitle('What do you need today?', 'All services')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.88,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final service = _services[index];
                    return _ServiceCard(
                      service: service,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ServiceBrowsePage(service: service.title))),
                    );
                  },
                  childCount: _services.length,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildLocationCard()),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          if (index == 0) {
            setState(() => _selectedTab = 0);
            return;
          }
          final page = index == 1
              ? const CustomerOrdersPage()
              : const CustomerAccountPage();
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Account'),
        ],
      ),
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Row(
          children: [
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF176B57),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.explore_rounded, color: Colors.white, size: 27),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DELIVERING TO', style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Color(0xFF737B76))),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 17, color: Color(0xFF176B57)),
                      SizedBox(width: 3),
                      Text('Choose your location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => _showComingSoon('Notifications'),
              icon: const Icon(Icons.notifications_none_rounded, size: 27),
            ),
          ],
        ),
      );

  Widget _buildSearch() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerSearchPage())),
          decoration: InputDecoration(
            hintText: 'Search food, shops, rides and more',
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF176B57)),
            suffixIcon: IconButton(
              tooltip: 'Search',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerSearchPage())),
              icon: const Icon(Icons.tune_rounded),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFFE7EBE7))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: const BorderSide(color: Color(0xFF176B57), width: 1.4)),
          ),
        ),
      );

  Widget _buildHeroBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF155C4B), Color(0xFF23866A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(30)),
                      child: const Text('ONE APP. MORE POSSIBILITIES.', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                    ),
                    const SizedBox(height: 13),
                    const Text('Your day,\nsimplified.', style: TextStyle(color: Colors.white, fontSize: 28, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                    const SizedBox(height: 10),
                    Text('The essentials of everyday life, together.', style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12, height: 1.4)),
                    const SizedBox(height: 15),
                    TextButton(
                      onPressed: () => _showComingSoon('Alteo services'),
                      style: TextButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF155C4B), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9), minimumSize: Size.zero),
                      child: const Text('Explore Alteo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                height: 104,
                width: 94,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(26)),
                child: const Icon(Icons.travel_explore_rounded, color: Colors.white, size: 66),
              ),
            ],
          ),
        ),
      );

  Widget _buildSectionTitle(String title, String action) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3))),
            TextButton(onPressed: () => _showComingSoon(action), child: Text(action)),
          ],
        ),
      );

  Widget _buildLocationCard() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<String>(builder: (_) => const CustomerLocationPage())).then((address) { if (address != null && mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected location: $address'))); } }),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE7EBE7))),
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(15)),
                  child: const Icon(Icons.map_outlined, color: Color(0xFF176B57), size: 26),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Set your delivery location', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      SizedBox(height: 4),
                      Text('Choose an address to see available services', style: TextStyle(color: Color(0xFF737B76), fontSize: 11, height: 1.3)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 15),
              ],
            ),
          ),
        ),
      );
}

class _ServiceItem {
  const _ServiceItem(this.title, this.subtitle, this.icon, this.background, this.foreground);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color background;
  final Color foreground;
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});
  final _ServiceItem service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 13, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: const Color(0xFFE8ECE8)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 51,
                  width: 51,
                  decoration: BoxDecoration(color: service.background, borderRadius: BorderRadius.circular(17)),
                  child: Icon(service.icon, color: service.foreground, size: 27),
                ),
                const SizedBox(height: 9),
                Text(service.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 4),
                Text(service.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Color(0xFF737B76))),
              ],
            ),
          ),
        ),
      );
}
