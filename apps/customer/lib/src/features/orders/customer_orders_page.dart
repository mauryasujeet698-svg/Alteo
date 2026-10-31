import 'package:flutter/material.dart';
import 'package:alteo_partner_ui/alteo_partner_ui.dart';
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
  Future<String>? _deliveryCodeFuture;

  @override
  void didUpdateWidget(covariant CustomerOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldStatus = oldWidget.order['status']?.toString();
    if (_status == 'out_for_delivery' && oldStatus != 'out_for_delivery') {
      _deliveryCodeFuture = Supabase.instance.client.rpc(
        'customer_get_delivery_verification_code',
        params: {'p_order_id': widget.order['id']},
      ).then((value) => value.toString());
    }
  }

  String get _status => widget.order['status']?.toString() ?? 'unknown';
  bool get _canCancelItems =>
      const ['cod_pending', 'accepted', 'preparing', 'ready_for_pickup'].contains(_status) &&
      widget.order['payment_method']?.toString() == 'cod' &&
      widget.order['payment_status']?.toString() == 'cod_pending';

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final rows = await Supabase.instance.client
        .from('order_items')
        .select('id,product_id,product_name_snapshot,quantity,unit_price_minor,line_total_minor,status')
        .eq('order_id', widget.order['id'])
        .order('created_at');
    final items = List<Map<String, dynamic>>.from(rows as List);
    final productIds = items
        .map((item) => item['product_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (productIds.isNotEmpty) {
      try {
        final products = await Supabase.instance.client
            .from('seller_products')
            .select('id,image_url')
            .inFilter('id', productIds);
        final urls = <String, String>{
          for (final product in (products as List).map((row) => Map<String, dynamic>.from(row as Map)))
            product['id'].toString(): (product['image_url'] ?? '').toString(),
        };
        for (final item in items) {
          item['image_url'] = urls[item['product_id']?.toString()] ?? '';
        }
      } catch (_) {}
    }
    return items;
  }

  Widget _thumbnail(String url) {
    if (!url.startsWith('https://')) {
      return const CircleAvatar(
        backgroundColor: Color(0xFFE3F2E9),
        child: Icon(Icons.inventory_2_outlined, color: Color(0xFF176B57)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AlteoNetworkImage(
        url: url,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        fallback: const CircleAvatar(
          backgroundColor: Color(0xFFE3F2E9),
          child: Icon(Icons.inventory_2_outlined, color: Color(0xFF176B57)),
        ),
      ),
    );
  }

  String _month(int month) => const [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec',
  ][month - 1];

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
    final createdAt = DateTime.tryParse(widget.order['created_at']?.toString() ?? '')?.toLocal();
    final placedLabel = createdAt == null
        ? 'Order placed'
        : 'Placed ${createdAt.day.toString().padLeft(2, '0')} ${_month(createdAt.month)} ${createdAt.year}';
    final progress = switch (rawStatus) {
      'cod_pending' || 'paid' => 0,
      'accepted' || 'preparing' => 1,
      'ready_for_pickup' => 2,
      'out_for_delivery' => 3,
      'completed' => 4,
      _ => -1,
    };
    final address = widget.order['delivery_address_snapshot'] is Map
        ? Map<String, dynamic>.from(widget.order['delivery_address_snapshot'] as Map)
        : <String, dynamic>{};
    final addressLabel = [
      address['address_line1'], address['locality'], address['city'],
      address['state'], address['postal_code'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join(', ');

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
          if (expanded) {
            setState(() {
              _itemsFuture ??= _loadItems();
              if (_status == 'out_for_delivery') {
                _deliveryCodeFuture ??= Supabase.instance.client.rpc(
                  'customer_get_delivery_verification_code',
                  params: {'p_order_id': widget.order['id']},
                ).then((value) => value.toString());
              }
            });
          }
        },
        children: [
          if (progress >= 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ORDER TRACKING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: Color(0xFF68736D))),
                const SizedBox(height: 7),
                LinearProgressIndicator(value: (progress + 1) / 5, minHeight: 6, backgroundColor: const Color(0xFFE7ECE8), color: const Color(0xFF176B57), borderRadius: BorderRadius.circular(8)),
                const SizedBox(height: 6),
                Text(const ['Order placed','Seller accepted','Ready for pickup','Out for delivery','Delivered'][progress], style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF176B57))),
              ]),
            )
          else if (rawStatus == 'cancelled' || rawStatus == 'refunded')
            const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Text('This order is no longer active.', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB3261E)))),
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
                      leading: _thumbnail(item['image_url']?.toString() ?? ''),
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
                  if (addressLabel.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF7F9F7), borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.home_outlined, color: Color(0xFF176B57)),
                        const SizedBox(width: 9),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('DELIVERY ADDRESS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .7, color: Color(0xFF68736D))),
                          const SizedBox(height: 3),
                          Text(addressLabel, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
                          if ((address['recipient_name']?.toString() ?? '').isNotEmpty || (address['phone']?.toString() ?? '').isNotEmpty)
                            Text([address['recipient_name'], address['phone']].where((v) => v != null && v.toString().isNotEmpty).join(' · '), style: const TextStyle(fontSize: 12, color: Color(0xFF68736D))),
                        ])),
                      ]),
                    ),
                  ],
                  if (_status == 'out_for_delivery') ...[
                    const SizedBox(height: 8),
                    FutureBuilder<String>(
                      future: _deliveryCodeFuture,
                      builder: (context, codeSnapshot) {
                        if (codeSnapshot.hasError) return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('Your delivery code will appear here when it is available.', style: TextStyle(color: Color(0xFF68736D))),
                        );
                        if (!codeSnapshot.hasData) return const Padding(
                          padding: EdgeInsets.all(16),
                          child: LinearProgressIndicator(),
                        );
                        return Container(
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFFE8F4ED), borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            const Icon(Icons.verified_user_outlined, color: Color(0xFF176B57)),
                            const SizedBox(width: 10),
                            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Share this delivery code', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF176B57))),
                              Text('Give it to your delivery partner only when your order arrives.', style: TextStyle(fontSize: 11, color: Color(0xFF52675D))),
                            ])),
                            Text(codeSnapshot.data!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3, color: Color(0xFF176B57))),
                          ]),
                        );
                      },
                    ),
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

class CustomerOrdersPage extends StatefulWidget {
  const CustomerOrdersPage({super.key});

  @override
  State<CustomerOrdersPage> createState() => _CustomerOrdersPageState();

  static String shortId(dynamic value) {
    final id = value?.toString() ?? '';
    return id.length > 8 ? id.substring(0, 8) : id.isEmpty ? '—' : id;
  }
}

class _CustomerOrdersPageState extends State<CustomerOrdersPage> {
  String filter = 'All';

  bool _matches(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? '';
    switch (filter) {
      case 'To confirm':
        return const {'cod_pending', 'paid'}.contains(status);
      case 'Preparing':
        return const {'accepted', 'preparing', 'ready_for_pickup'}.contains(status);
      case 'To receive':
        return status == 'out_for_delivery';
      case 'Completed':
        return status == 'completed';
      case 'Cancelled':
        return const {'cancelled', 'refunded', 'refund_pending'}.contains(status);
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('My orders', style: TextStyle(fontWeight: FontWeight.w900))),
      body: user == null
        ? Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(height: 88, width: 88, decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(28)), child: const Icon(Icons.receipt_long_rounded, size: 42, color: Color(0xFF176B57))),
              const SizedBox(height: 20),
              const Text('Sign in to view your orders', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Your shopping orders, delivery progress and order details will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF737B76), height: 1.5)),
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const CustomerAuthPage())), icon: const Icon(Icons.login_rounded), label: const Text('Sign in with Google')),
            ]),
          ))
        : StreamBuilder<List<Map<String, dynamic>>>(
            stream: client.from('orders').stream(primaryKey: ['id']).eq('customer_id', user.id).order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Your orders could not load. Check your connection and try again.')));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final orders = snapshot.data!.where(_matches).toList();
              return Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  color: Colors.white,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Track, manage and review your purchases', style: TextStyle(color: Color(0xFF68736D))),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final label in const ['All','To confirm','Preparing','To receive','Completed','Cancelled'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: filter == label,
                              onSelected: (_) => setState(() => filter = label),
                              selectedColor: const Color(0xFFD7EEE3),
                              side: BorderSide(color: filter == label ? const Color(0xFF176B57) : const Color(0xFFE1E7E2)),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                ),
                Expanded(
                  child: orders.isEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF176B57)),
                          const SizedBox(height: 12),
                          Text(filter == 'All' ? 'No orders yet' : 'No $filter orders', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 5),
                          const Text('Your shopping orders will appear here after checkout.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF68736D))),
                        ]),
                      ))
                    : RefreshIndicator(
                        onRefresh: () async { setState(() {}); },
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
                          children: orders.map((order) => CustomerOrderCard(order: order)).toList(),
                        ),
                      ),
                ),
              ]);
            },
          ),
    );
  }
}

class CustomerTripsPage extends StatefulWidget {
  const CustomerTripsPage({super.key, this.initialTab = 'rides'});
  final String initialTab;

  @override
  State<CustomerTripsPage> createState() => _CustomerTripsPageState();
}

class _CustomerTripsPageState extends State<CustomerTripsPage> {
  late String selected;

  @override
  void initState() {
    super.initState();
    selected = widget.initialTab == 'parcels' ? 'parcels' : 'rides';
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Rides & parcels', style: TextStyle(fontWeight: FontWeight.w900))),
      body: user == null
        ? Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.route_rounded, size: 48, color: Color(0xFF176B57)),
              const SizedBox(height: 14),
              const Text('Sign in to view your activity', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 8),
              const Text('Your ride and parcel history will appear here.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const CustomerAuthPage())), icon: const Icon(Icons.login_rounded), label: const Text('Sign in with Google')),
            ]),
          ))
        : Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Expanded(child: ChoiceChip(
                  avatar: const Icon(Icons.directions_car_rounded, size: 18),
                  label: const Text('Rides'),
                  selected: selected == 'rides',
                  onSelected: (_) => setState(() => selected = 'rides'),
                  selectedColor: const Color(0xFFD7EEE3),
                )),
                const SizedBox(width: 10),
                Expanded(child: ChoiceChip(
                  avatar: const Icon(Icons.local_shipping_rounded, size: 18),
                  label: const Text('Parcels'),
                  selected: selected == 'parcels',
                  onSelected: (_) => setState(() => selected = 'parcels'),
                  selectedColor: const Color(0xFFD7EEE3),
                )),
              ]),
            ),
            Expanded(child: selected == 'rides' ? _rides(client, user.id) : _parcels(client, user.id)),
          ]),
    );
  }

  Widget _rides(SupabaseClient client, String userId) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: client.from('rides').stream(primaryKey: ['id']).eq('customer_id', userId).order('created_at', ascending: false),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Could not load rides. Please refresh and try again.'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final rides = snapshot.data!;
      if (rides.isEmpty) return const Center(child: Text('No rides yet. Your ride requests will appear here.'));
      return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: rides.map((ride) {
        final fare = (((ride['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0);
        return Card(elevation: 0, color: Colors.white, margin: const EdgeInsets.only(bottom: 10), child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFFFFF0C7), child: Icon(Icons.directions_car_rounded, color: Color(0xFF8C6410))),
          title: Text((ride['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (ride['destination_label']?.toString() ?? 'Destination'), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Status: ' + (ride['status']?.toString() ?? 'requested').replaceAll('_', ' ') + ' · Fare ₹$fare'),
          trailing: TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerLiveTrackingPage(entityType: 'ride', entityId: ride['id'].toString()))),
            icon: const Icon(Icons.my_location_rounded, size: 17),
            label: const Text('Track'),
          ),
        ));
      }).toList());
    },
  );

  Widget _parcels(SupabaseClient client, String userId) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: client.from('delivery_jobs').stream(primaryKey: ['id']).eq('customer_id', userId).order('created_at', ascending: false),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Could not load parcels. Please refresh and try again.'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final jobs = snapshot.data!.where((job) => job['job_type'] == 'parcel').toList();
      if (jobs.isEmpty) return const Center(child: Text('No parcels yet. Your parcel requests will appear here.'));
      return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), children: jobs.map((job) {
        final fare = (((job['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0);
        return Card(elevation: 0, color: Colors.white, margin: const EdgeInsets.only(bottom: 10), child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFFDDF3F1), child: Icon(Icons.local_shipping_rounded, color: Color(0xFF187B73))),
          title: Text((job['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (job['destination_label']?.toString() ?? 'Destination'), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Status: ' + (job['status']?.toString() ?? 'pending').replaceAll('_', ' ') + ' · Fare ₹$fare'),
          trailing: TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerLiveTrackingPage(entityType: 'parcel', entityId: job['id'].toString()))),
            icon: const Icon(Icons.location_searching_rounded, size: 17),
            label: const Text('Track'),
          ),
        ));
      }).toList());
    },
  );
}
