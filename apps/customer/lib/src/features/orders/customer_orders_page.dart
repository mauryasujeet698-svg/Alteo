import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';

class CustomerOrdersPage extends StatelessWidget {
  const CustomerOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Your orders')),
      body: user == null
        ? Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(height: 88, width: 88, decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(28)), child: const Icon(Icons.receipt_long_rounded, size: 42, color: Color(0xFF176B57))),
              const SizedBox(height: 20),
              const Text('Explore first, sign in when needed', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Browsing Alteo is open. Sign in only when you want to view your private order history.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF737B76), height: 1.5)),
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const CustomerAuthPage())), icon: const Icon(Icons.login_rounded), label: const Text('Sign in to view orders')),
            ]),
          ))
        : StreamBuilder<List<Map<String, dynamic>>>(
            stream: client.from('orders').stream(primaryKey: ['id']).eq('customer_id', user.id).order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Could not load order history. Confirm the shared operations migration and customer read policy are applied.')));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final orders = snapshot.data!;
              if (orders.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long_outlined, size: 54, color: Color(0xFF176B57)),
                SizedBox(height: 14),
                Text('No orders yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('Your orders will appear here and update as the seller, admin and delivery partner process them.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF737B76), height: 1.5)),
              ])));
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final total = (((order['total_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0);
                  final status = (order['status'] as String? ?? 'pending').replaceAll('_', ' ');
                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE5EAE5))),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2E9), child: Icon(Icons.receipt_long_rounded, color: Color(0xFF176B57))),
                      title: Text('Order ' + _shortId(order['id']), style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('Status: ' + status + '\nTotal: ₹' + total),
                      isThreeLine: true,
                    ),
                  );
                },
              );
            },
          ),
    );
  }

  String _shortId(dynamic value) {
    final id = value?.toString() ?? '';
    return id.length > 8 ? id.substring(0, 8) : id.isEmpty ? '—' : id;
  }
}
