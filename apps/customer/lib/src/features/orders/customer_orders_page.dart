import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';
import 'customer_live_tracking_page.dart';

class CustomerOrderCard extends StatefulWidget {
  const CustomerOrderCard({super.key, required this.order});
  final Map<String, dynamic> order;

  @override
  State<CustomerOrderCard> createState() => _CustomerOrderCardState();
}

class _CustomerOrderCardState extends State<CustomerOrderCard> {
  Future<List<Map<String, dynamic>>>? _itemsFuture;

  String get _status => widget.order['status']?.toString() ?? 'unknown';
  bool get _canCancelItems =>
      const ['cod_pending', 'accepted', 'preparing', 'ready_for_pickup'].contains(_status) &&
      widget.order['payment_method']?.toString() == 'cod' &&
      widget.order['payment_status']?.toString() == 'cod_pending';

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final rows = await Supabase.instance.client
        .from('order_items')
        .select('id,product_name_snapshot,quantity,unit_price_minor,line_total_minor,status')
        .eq('order_id', widget.order['id'])
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> _cancelItem(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this item?'),
        content: Text('Cancel ${item['product_name_snapshot'] ?? 'this item'} from your order? Other items in the order will remain active.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep item')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel item')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('customer_cancel_order_item', params: {
        'p_order_item_id': item['id'],
        'p_reason': 'Customer requested cancellation',
      }).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _itemsFuture = _loadItems());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item cancelled successfully. Your order total has been updated.')));
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString().toLowerCase();
      final message = raw.contains('out for delivery')
          ? 'This item can no longer be cancelled because the order is out for delivery.'
          : raw.contains('refund')
              ? 'This payment needs Admin support to arrange a refund.'
              : 'We could not cancel this item. Refresh the order and try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = (((widget.order['total_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0);
    final rawStatus = _status;
    final status = rawStatus == 'cod_pending'
        ? 'Placed · awaiting seller acceptance'
        : rawStatus.replaceAll('_', ' ');
    final method = widget.order['payment_method']?.toString() ?? '';
    final paymentStatus = widget.order['payment_status']?.toString() ?? 'pending';
    final payment = method == 'cod'
        ? (paymentStatus == 'paid' ? 'Cash on delivery · collected' : 'Cash on delivery · pay when it arrives')
        : paymentStatus.replaceAll('_', ' ');

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE3F2E9),
          child: Icon(Icons.receipt_long_rounded, color: Color(0xFF176B57)),
        ),
        title: Text('Order ${CustomerOrdersPage.shortId(widget.order['id'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('Status: $status\nPayment: $payment · Total ₹$total'),
        onExpansionChanged: (expanded) {
          if (expanded && _itemsFuture == null) {
            setState(() => _itemsFuture = _loadItems());
          }
        },
        children: [
          if (_itemsFuture == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Expand to view the items in this order.'),
            )
          else
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _itemsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Order items could not load. Please refresh and try again.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  );
                }
                if (snapshot.data!.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No items are attached to this order.'),
                  );
                }
                return Column(children: [
                  for (final item in snapshot.data!) ...[
                    ListTile(
                      title: Text(
                        item['product_name_snapshot']?.toString() ?? 'Item',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: item['status'] == 'cancelled' ? TextDecoration.lineThrough : null,
                          color: item['status'] == 'cancelled' ? const Color(0xFF858D87) : null,
                        ),
                      ),
                      subtitle: Text(
                        'Qty ${item['quantity']} · ₹${(((item['unit_price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)} each',
                      ),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('₹${(((item['line_total_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)}'),
                          if (item['status'] == 'cancelled')
                            const Text('Cancelled', style: TextStyle(fontSize: 11, color: Color(0xFF858D87)))
                          else if (_canCancelItems)
                            TextButton(
                              onPressed: () => _cancelItem(item),
                              child: const Text('Cancel item'),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, indent: 16),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (_canCancelItems)
                          const Expanded(child: Text('Items can be cancelled until the order is out for delivery.', style: TextStyle(fontSize: 12, color: Color(0xFF68736D))))
                        else
                          const Expanded(child: Text('Cancellation is unavailable at this order stage.', style: TextStyle(fontSize: 12, color: Color(0xFF68736D)))),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => CustomerLiveTrackingPage(entityType: 'order', entityId: widget.order['id'].toString()),
                          )),
                          icon: const Icon(Icons.location_searching_rounded, size: 17),
                          label: const Text('Track'),
                        ),
                      ],
                    ),
                  ),
                ]);
              },
            ),
        ],
      ),
    );
  }
}

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
      return Column(children: orders.map((order) => CustomerOrderCard(order: order)).toList());
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

  static String shortId(dynamic value) {
    final id = value?.toString() ?? '';
    return id.length > 8 ? id.substring(0, 8) : id.isEmpty ? '—' : id;
  }
}
