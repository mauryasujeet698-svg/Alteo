import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';
import 'customer_live_tracking_page.dart';

class CustomerOrdersPage extends StatelessWidget {
  const CustomerOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Your activity')),
      body: user == null
        ? Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(height: 88, width: 88, decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(28)), child: const Icon(Icons.receipt_long_rounded, size: 42, color: Color(0xFF176B57))),
              const SizedBox(height: 20),
              const Text('Explore first, sign in when needed', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Browsing Alteo is open. Sign in only when you want to view your private order, ride and parcel history.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF737B76), height: 1.5)),
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const CustomerAuthPage())), icon: const Icon(Icons.login_rounded), label: const Text('Sign in to view activity')),
            ]),
          ))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Shopping and food orders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              _orders(client, user.id),
              const SizedBox(height: 22),
              const Text('Rides', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              _rides(client, user.id),
              const SizedBox(height: 22),
              const Text('Parcels and deliveries', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              _parcels(client, user.id),
            ],
          ),
    );
  }

  Widget _orders(SupabaseClient client, String userId) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: client.from('orders').stream(primaryKey: ['id']).eq('customer_id', userId).order('created_at', ascending: false),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _error('Your orders could not load. Check your connection and try again.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final orders = snapshot.data!;
      if (orders.isEmpty) return _empty('No orders yet', 'Orders will appear here after checkout.');
      return Column(children: orders.map((order) {
        final total = (((order['total_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0);
        final rawStatus = order['status']?.toString() ?? 'unknown';
        final status = rawStatus == 'cod_pending' ? 'Placed · awaiting seller acceptance' : rawStatus.replaceAll('_', ' ');
        final method = order['payment_method']?.toString() ?? '';
        final paymentStatus = order['payment_status']?.toString() ?? 'pending';
        final payment = method == 'cod'
            ? (paymentStatus == 'paid' ? 'Cash on delivery · collected' : 'Cash on delivery · pay when it arrives')
            : paymentStatus.replaceAll('_', ' ');
        return Card(elevation: 0, color: Colors.white, margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2E9), child: Icon(Icons.receipt_long_rounded, color: Color(0xFF176B57))),
          title: Text('Order ' + _shortId(order['id']), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Status: ' + status + '\nPayment: ' + payment + ' · Total ₹' + total),
          isThreeLine: true,
          trailing: TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerLiveTrackingPage(entityType: 'order', entityId: order['id'].toString()))),
            icon: const Icon(Icons.location_searching_rounded, size: 17),
            label: const Text('Track'),
          ),
        ));
      }).toList());
    },
  );

  Widget _rides(SupabaseClient client, String userId) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: client.from('rides').stream(primaryKey: ['id']).eq('customer_id', userId).order('created_at', ascending: false),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _error('Could not load rides.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final rides = snapshot.data!;
      if (rides.isEmpty) return _empty('No rides yet', 'Your ride requests and trip status will appear here.');
      return Column(children: rides.map((ride) => Card(elevation: 0, color: Colors.white, margin: const EdgeInsets.only(bottom: 8), child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFFFF0C7), child: Icon(Icons.directions_car_rounded, color: Color(0xFF8C6410))),
        title: Text((ride['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (ride['destination_label']?.toString() ?? 'Destination'), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('Status: ' + (ride['status']?.toString() ?? 'requested').replaceAll('_', ' ') + ' · Fare ₹' + (((ride['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
        trailing: TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerLiveTrackingPage(entityType: 'ride', entityId: ride['id'].toString()))),
          icon: const Icon(Icons.my_location_rounded, size: 17),
          label: const Text('Track'),
        ),
      ))).toList());
    },
  );

  Widget _parcels(SupabaseClient client, String userId) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: client.from('delivery_jobs').stream(primaryKey: ['id']).eq('customer_id', userId).order('created_at', ascending: false),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _error('Could not load parcels and deliveries.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final jobs = snapshot.data!.where((job) => job['job_type'] == 'parcel').toList();
      if (jobs.isEmpty) return _empty('No parcels yet', 'Your parcel requests and delivery status will appear here.');
      return Column(children: jobs.map((job) => Card(elevation: 0, color: Colors.white, margin: const EdgeInsets.only(bottom: 8), child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFDDF3F1), child: Icon(Icons.local_shipping_rounded, color: Color(0xFF187B73))),
        title: Text((job['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (job['destination_label']?.toString() ?? 'Destination'), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('Status: ' + (job['status']?.toString() ?? 'pending').replaceAll('_', ' ') + ' · Fare ₹' + (((job['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
        trailing: TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerLiveTrackingPage(entityType: 'parcel', entityId: job['id'].toString()))),
          icon: const Icon(Icons.location_searching_rounded, size: 17),
          label: const Text('Track'),
        ),
      ))).toList());
    },
  );

  Widget _empty(String title, String detail) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EAE5))),
    child: Column(children: [const Icon(Icons.inbox_outlined, size: 34, color: Color(0xFF176B57)), const SizedBox(height: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF737B76), height: 1.4))]),
  );

  Widget _error(String text) => Padding(padding: const EdgeInsets.all(12), child: Text(text, style: const TextStyle(color: Colors.red, height: 1.4)));

  String _shortId(dynamic value) {
    final id = value?.toString() ?? '';
    return id.length > 8 ? id.substring(0, 8) : id.isEmpty ? '—' : id;
  }
}
