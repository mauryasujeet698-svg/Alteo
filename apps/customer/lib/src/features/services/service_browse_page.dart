import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';

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
                onTap: () {
                  if (service == 'Rides' && (option.title == 'Bike ride' || option.title == 'Car ride')) {
                    _requestService(context, 'ride');
                  } else if (service == 'Parcel' && option.title == 'Send a parcel') {
                    _requestService(context, 'parcel');
                  } else {
                    showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(option.title), content: const Text('Explore this section without signing in. Live listings and availability appear when the corresponding partners and backend data are configured.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))]));
                  }
                },
              ),
            ),
        ],
      ),
    );
  }


  Future<void> _requestService(BuildContext context, String type) async {
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      _showMessage(context, 'The booking backend is unavailable right now. You can continue exploring this service.');
      return;
    }

    if (client.auth.currentUser == null) {
      await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
      if (!context.mounted) return;
      if (client.auth.currentUser == null) {
        _showMessage(context, 'You can explore without signing in. Sign-in is required only to place a real request.');
        return;
      }
    }

    final pickup = TextEditingController();
    final dropoff = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text(type == 'ride' ? 'Request a ride' : 'Send a parcel'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: pickup, minLines: 1, maxLines: 2, decoration: const InputDecoration(labelText: 'Pickup location', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: dropoff, minLines: 1, maxLines: 2, decoration: InputDecoration(labelText: type == 'ride' ? 'Destination' : 'Delivery address', border: const OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit request')),
        ],
      ));
      if (confirmed != true || !context.mounted) return;
      if (pickup.text.trim().length < 4 || dropoff.text.trim().length < 4) {
        _showMessage(context, 'Enter both pickup and destination details.');
        return;
      }
      final user = client.auth.currentUser;
      if (user == null) return;
      await client.from('service_requests').insert({
        'customer_id': user.id,
        'service_type': type,
        'status': 'requested',
        'pickup': {'address_line': pickup.text.trim()},
        'dropoff': {'address_line': dropoff.text.trim()},
      });
      if (context.mounted) _showMessage(context, type == 'ride' ? 'Ride request submitted. Availability depends on nearby eligible drivers.' : 'Parcel request submitted. Availability depends on delivery partner coverage.');
    } catch (e) {
      if (context.mounted) _showMessage(context, 'Could not submit the request. Confirm the shared operations migration is applied. ' + e.toString());
    } finally {
      pickup.dispose();
      dropoff.dispose();
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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