import 'package:flutter/material.dart';

class ServiceBrowsePage extends StatelessWidget {
  const ServiceBrowsePage({super.key, required this.service});
  final String service;

  static const Map<String, List<_Option>> _options = {
    'Food': [
      _Option('Restaurants', 'Explore local restaurants and menus', Icons.restaurant_rounded),
      _Option('Meals', 'Everyday meals and family options', Icons.dinner_dining_rounded),
      _Option('Snacks & drinks', 'Quick bites and refreshments', Icons.local_cafe_rounded),
    ],
    'Quick': [
      _Option('Fresh groceries', 'Fruit, vegetables and staples', Icons.eco_rounded),
      _Option('Dairy & breakfast', 'Milk, bread and breakfast needs', Icons.breakfast_dining_rounded),
      _Option('Home essentials', 'Household basics', Icons.cleaning_services_rounded),
    ],
    'Shop': [
      _Option('Everyday shopping', 'Discover useful daily products', Icons.shopping_bag_rounded),
      _Option('Personal care', 'Personal care essentials', Icons.spa_rounded),
      _Option('Home & living', 'Items for your home', Icons.chair_alt_rounded),
    ],
    'Rides': [
      _Option('Bike ride', 'A convenient solo ride', Icons.two_wheeler_rounded),
      _Option('Car ride', 'Point-to-point travel', Icons.directions_car_rounded),
      _Option('Safety information', 'Read ride safety guidance', Icons.shield_outlined),
    ],
    'Parcel': [
      _Option('Send a parcel', 'Prepare a local delivery', Icons.local_shipping_rounded),
      _Option('Track a parcel', 'Track an existing delivery', Icons.location_searching_rounded),
      _Option('Packaging guide', 'Prepare a parcel for pickup', Icons.inventory_2_outlined),
    ],
    'More': [
      _Option('Food', 'Meals and restaurants', Icons.restaurant_rounded),
      _Option('Quick commerce', 'Everyday essentials', Icons.shopping_basket_rounded),
      _Option('Rides & parcels', 'Travel and local delivery', Icons.route_rounded),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final options = _options[service] ?? _options['More']!;
    return Scaffold(
      appBar: AppBar(title: Text(service)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_heading, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Explore the options below. Live availability, prices and bookings require the Alteo backend and participating local partners to be configured.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
          const SizedBox(height: 18),
          for (final option in options)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5EAE5))),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(backgroundColor: const Color(0xFFE3F2E9), child: Icon(option.icon, color: const Color(0xFF176B57))),
                title: Text(option.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(option.subtitle)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(option.title), content: const Text('This service screen is ready for integration. Live results and bookings will be enabled when the relevant backend endpoints and service partners are available.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))])),
              ),
            ),
        ],
      ),
    );
  }

  String get _heading => switch (service) {
    'Food' => 'Good food, made easy',
    'Quick' => 'Everyday essentials',
    'Shop' => 'Find your everyday favourites',
    'Rides' => 'Where would you like to go?',
    'Parcel' => 'Send something with care',
    _ => 'Explore Alteo services',
  };
}

class _Option {
  const _Option(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}