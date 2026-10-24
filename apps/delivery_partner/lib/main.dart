import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  SupabaseClient? client;
  String? error;
  if (url.isEmpty || key.isEmpty) {
    error = 'Build with SUPABASE_URL and SUPABASE_ANON_KEY to connect Alteo.';
  } else {
    try {
      await Supabase.initialize(url: url, anonKey: key);
      client = Supabase.instance.client;
    } catch (_) {
      error = 'Supabase could not be initialized. Check app configuration.';
    }
  }
  runApp(AlteoDeliveryApp(client: client, configError: error));
}

class AlteoDeliveryApp extends StatelessWidget {
  const AlteoDeliveryApp({super.key, required this.client, required this.configError});
  final SupabaseClient? client;
  final String? configError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Alteo Delivery Partner',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F6)),
    home: client == null ? _ConfigScreen(message: configError ?? 'Configuration needed.') : _AuthGate(client: client!),
  );
}

class _ConfigScreen extends StatelessWidget {
  const _ConfigScreen({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.delivery_dining, size: 62, color: Color(0xFF176B57)),
      const SizedBox(height: 12), Text('Alteo Delivery Partner', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12), Text(message, textAlign: TextAlign.center),
    ]),
  ))));
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.client});
  final SupabaseClient client;
  @override
  State<_AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<_AuthGate> {
  User? _user;
  late final StreamSubscription<AuthState> _subscription;
  @override
  void initState() {
    super.initState();
    _user = widget.client.auth.currentUser;
    _subscription = widget.client.auth.onAuthStateChange.listen((event) {
      if (mounted) setState(() => _user = event.session?.user);
    });
  }
  @override
  void dispose() { _subscription.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => _user == null
    ? _LoginScreen(client: widget.client)
    : _DeliveryRoleGate(client: widget.client, user: _user!);
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<_LoginScreen> createState() => __LoginScreenState();
}
class __LoginScreenState extends State<_LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _googleSignIn() async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'alteo://login-callback',
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Google sign-in could not start. Check that Google is enabled in Supabase Auth and the Alteo redirect URL is allowed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.delivery_dining, size: 62, color: const Color(0xFF176B57)),
                const SizedBox(height: 16),
                Text("Delivery partner sign-in", textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text("Sign in with Google using your approved Alteo delivery-partner account.", textAlign: TextAlign.center),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _busy ? null : _googleSignIn,
                  icon: const Icon(Icons.g_mobiledata, size: 30),
                  label: const Text('Sign in with Google'),
                ),
                if (_busy) const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                if (_error != null) Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DeliveryRoleGate extends StatefulWidget {
  const _DeliveryRoleGate({required this.client, required this.user});
  final SupabaseClient client;
  final User user;
  @override
  State<_DeliveryRoleGate> createState() => _DeliveryRoleGateState();
}
class _DeliveryRoleGateState extends State<_DeliveryRoleGate> {
  late Future<bool> _access;
  @override
  void initState() { super.initState(); _access = _check(); }
  Future<bool> _check() async {
    final rows = await widget.client.from('user_roles').select('role')
      .eq('user_id', widget.user.id).eq('role', 'delivery_partner').limit(1);
    return rows.isNotEmpty;
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(future: _access, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (snapshot.hasError || snapshot.data != true) {
      return Scaffold(appBar: AppBar(title: const Text('Delivery partner')), body: Center(child: Padding(
        padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 48), const SizedBox(height: 12),
          const Text('Partner access has not been approved for this account.', textAlign: TextAlign.center),
          const SizedBox(height: 12), OutlinedButton(onPressed: () async => widget.client.auth.signOut(), child: const Text('Sign out')),
        ]),
      )));
    }
    return _DeliveryHome(client: widget.client, user: widget.user);
  });
}

class _Task {
  const _Task(this.job, this.assignmentStatus);
  final Map<String, dynamic> job;
  final String? assignmentStatus;
  String get id => job['id'].toString();
  String get status => job['status']?.toString() ?? 'pending';
  bool get isParcel => job['job_type'] == 'parcel';
  bool get isOrder => job['order_id'] != null;
}

class _DeliveryHome extends StatefulWidget {
  const _DeliveryHome({required this.client, required this.user});
  final SupabaseClient client;
  final User user;
  @override
  State<_DeliveryHome> createState() => _DeliveryHomeState();
}
class _DeliveryHomeState extends State<_DeliveryHome> {
  late Future<List<_Task>> _tasks;
  late Future<List<Map<String, dynamic>>> _earnings;
  final _area = TextEditingController(text: 'DEFAULT');
  bool _working = true;
  bool _online = false;
  bool _availabilityBusy = false;
  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { _area.dispose(); super.dispose(); }
  Future<List<_Task>> _loadTasks() async {
    final rows = await widget.client.from('delivery_jobs')
      .select('id,order_id,customer_id,seller_id,status,job_type,tracking_code,pickup_label,destination_label,item_description,fare_minor,created_at')
      .eq('delivery_partner_id', widget.user.id).order('created_at', ascending: false).limit(100);
    final jobs = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    final output = <_Task>[];
    for (final job in jobs) {
      final assignments = await widget.client.from('delivery_assignments').select('status')
        .eq('delivery_job_id', job['id']).eq('partner_id', widget.user.id)
        .order('created_at', ascending: false).limit(1);
      final assignmentStatus = assignments.isEmpty ? null : assignments.first['status']?.toString();
      output.add(_Task(job, assignmentStatus));
    }
    return output;
  }
  void _refresh() {
    _tasks = _loadTasks();
    _earnings = widget.client.from('delivery_earnings')
      .select('id,amount_minor,currency,status,created_at')
      .eq('delivery_partner_id', widget.user.id).order('created_at', ascending: false).limit(100)
      .then((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }
  Future<void> _toggleAvailability(bool online) async {
    setState(() => _availabilityBusy = true);
    try {
      await widget.client.rpc('partner_set_availability', params: {
        'p_role': 'delivery_partner',
        'p_area_code': _area.text.trim().isEmpty ? 'DEFAULT' : _area.text.trim().toUpperCase(),
        'p_is_online': online,
        'p_latitude': null,
        'p_longitude': null,
      });
      if (mounted) {
        setState(() => _online = online);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(online ? 'You are online for delivery assignment.' : 'You are offline.')));
      }
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update availability.')));
    } finally { if (mounted) setState(() => _availabilityBusy = false); }
  }
  Future<void> _action(_Task task, String action) async {
    setState(() => _working = true);
    try {
      await widget.client.rpc('partner_update_delivery_status', params: {
        'p_delivery_job_id': task.id, 'p_action': action,
      });
      if (mounted) {
        setState(_refresh);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delivery updated: ' + action.replaceAll('_', ' '))));
      }
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update delivery status.')));
    } finally { if (mounted) setState(() => _working = false); }
  }
  Future<List<Map<String, dynamic>>> _items(String orderId) async {
    final rows = await widget.client.from('order_items')
      .select('id,product_name_snapshot,quantity,unit_price_minor,line_total_minor')
      .eq('order_id', orderId).order('created_at');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My deliveries', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: () => setState(_refresh), icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'Sign out', onPressed: () async => widget.client.auth.signOut(), icon: const Icon(Icons.logout)),
      ]),
    body: RefreshIndicator(onRefresh: () async { setState(_refresh); await Future.wait([_tasks, _earnings]); },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Assigned to you', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Only jobs assigned to your account are shown. Order item details are limited to your assigned orders.'),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          TextField(controller: _area, textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Service area code', helperText: 'Use the area code provided by Alteo operations.')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Available for automatic assignment'),
            subtitle: Text(_online ? 'Online' : 'Offline'),
            value: _online,
            onChanged: _availabilityBusy ? null : _toggleAvailability,
          ),
        ]))),

        const SizedBox(height: 12),
        FutureBuilder<List<_Task>>(future: _tasks, builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          if (snapshot.hasError) return const _DeliveryNotice(title: 'Could not load tasks', detail: 'Check network and assigned-task permissions, then refresh.');
          final tasks = snapshot.data ?? [];
          if (tasks.isEmpty) return const _DeliveryNotice(title: 'No assigned deliveries', detail: 'New tasks appear after Alteo operations assigns them to you.');
          return Column(children: tasks.map((task) {
            final fare = ((task.job['fare_minor'] as num?)?.toInt() ?? 0) / 100;
            final closed = ['delivered','cancelled','failed'].contains(task.status);
            final offered = task.assignmentStatus == 'offered';
            final accepted = task.assignmentStatus == 'accepted';
            return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(task.isParcel ? Icons.local_shipping_outlined : Icons.shopping_bag_outlined, color: const Color(0xFF176B57)),
                const SizedBox(width: 8),
                Expanded(child: Text(task.isParcel ? 'Parcel delivery' : 'Order delivery',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Chip(label: Text(task.status.replaceAll('_', ' '))),
              ]),
              const SizedBox(height: 8),
              if ((task.job['pickup_label']?.toString() ?? '').isNotEmpty) Text('Pickup: ' + task.job['pickup_label'].toString()),
              if ((task.job['destination_label']?.toString() ?? '').isNotEmpty) Text('Drop-off: ' + task.job['destination_label'].toString()),
              if (task.isParcel && (task.job['item_description']?.toString() ?? '').isNotEmpty) Text('Parcel: ' + task.job['item_description'].toString()),
              Text('Reference: ' + task.id.substring(0, 8).toUpperCase()),
              if (task.job['tracking_code'] != null) Text('Tracking: ' + task.job['tracking_code'].toString()),
              Text('Displayed fare: ₹' + fare.toStringAsFixed(2)),
              if (task.isOrder) ...[
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(future: _items(task.job['order_id'].toString()), builder: (context, itemSnapshot) {
                  if (itemSnapshot.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                  if (itemSnapshot.hasError) return const Text('Item details unavailable. Refresh or contact Alteo support.');
                  final items = itemSnapshot.data ?? [];
                  if (items.isEmpty) return const Text('No item lines found for this order.');
                  return ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Order items (' + items.length.toString() + ')'),
                    children: items.map((item) {
                      final price = ((item['unit_price_minor'] as num?)?.toInt() ?? 0) / 100;
                      return ListTile(
                        dense: true,
                        title: Text(item['product_name_snapshot']?.toString() ?? 'Item'),
                        subtitle: Text('Quantity: ' + item['quantity'].toString() + ' • Unit ₹' + price.toStringAsFixed(2)),
                      );
                    }).toList(),
                  );
                }),
              ],
              if (!closed) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  if (offered) ...[
                    FilledButton.tonal(onPressed: _working ? null : () => _action(task, 'accept'), child: const Text('Accept')),
                    TextButton(onPressed: _working ? null : () => _action(task, 'reject'), child: const Text('Reject')),
                  ],
                  if (accepted && task.status == 'assigned')
                    FilledButton(onPressed: _working ? null : () => _action(task, 'picked_up'), child: const Text('Picked up')),
                  if (task.status == 'picked_up')
                    FilledButton(onPressed: _working ? null : () => _action(task, 'in_transit'), child: const Text('Start delivery')),
                  if (task.status == 'in_transit')
                    FilledButton(onPressed: _working ? null : () => _action(task, 'delivered'), child: const Text('Mark delivered')),
                ]),
              ],
            ])));
          }).toList());
        }),
        const SizedBox(height: 22),
        Text('Earnings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        FutureBuilder<List<Map<String, dynamic>>>(future: _earnings, builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LinearProgressIndicator();
          if (snapshot.hasError) return const Text('Earnings unavailable.');
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) return const Text('Earnings will appear after completed work is reconciled.');
          final total = rows.fold<int>(0, (sum, row) => sum + ((row['amount_minor'] as num?)?.toInt() ?? 0));
          return Card(child: ListTile(
            leading: const Icon(Icons.currency_rupee, color: Color(0xFF176B57)),
            title: Text('Recorded earnings: ₹' + (total / 100).toStringAsFixed(2)),
            subtitle: Text(rows.length.toString() + ' earning records (subject to settlement reconciliation)'),
          ));
        }),
      ]),
    ),
  );
}

class _DeliveryNotice extends StatelessWidget {
  const _DeliveryNotice({required this.title, required this.detail});
  final String title, detail;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(24), child: Column(children: [
    const Icon(Icons.inbox_outlined, size: 42), const SizedBox(height: 10),
    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    const SizedBox(height: 6), Text(detail, textAlign: TextAlign.center),
  ]));
}
