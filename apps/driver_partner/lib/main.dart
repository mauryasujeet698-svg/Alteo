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
    } catch (_) { error = 'Supabase could not be initialized. Check app configuration.'; }
  }
  runApp(AlteoDriverApp(client: client, configError: error));
}

class AlteoDriverApp extends StatelessWidget {
  const AlteoDriverApp({super.key, required this.client, required this.configError});
  final SupabaseClient? client;
  final String? configError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Alteo Driver Partner', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)),
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
      const Icon(Icons.directions_car, size: 62, color: Color(0xFF176B57)),
      const SizedBox(height: 12), Text('Alteo Driver Partner', style: Theme.of(context).textTheme.headlineSmall),
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
  Widget build(BuildContext context) => _user == null ? _LoginScreen(client: widget.client) : _RoleGate(client: widget.client, user: _user!);
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.client});
  final SupabaseClient client;
  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<_LoginScreen> {
  final _phone = TextEditingController(), _otp = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;
  @override
  void dispose() { _phone.dispose(); _otp.dispose(); super.dispose(); }
  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (!_sent && !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
      setState(() => _error = 'Enter phone with country code, e.g. +919876543210.'); return;
    }
    if (_sent && !RegExp(r'^\d{6}$').hasMatch(_otp.text.trim())) {
      setState(() => _error = 'Enter the six-digit code.'); return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (!_sent) {
        await widget.client.auth.signInWithOtp(phone: phone);
        if (mounted) setState(() => _sent = true);
      } else {
        await widget.client.auth.verifyOTP(phone: phone, token: _otp.text.trim(), type: OtpType.sms);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in failed. Check SMS provider settings.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.directions_car, size: 62, color: Color(0xFF176B57)),
        const SizedBox(height: 14), Text('Driver partner sign-in', textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8), const Text('Sign in with your approved Alteo driver phone number.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextField(controller: _phone, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+919876543210')),
        if (_sent) ...[
          const SizedBox(height: 12), TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6,
            decoration: const InputDecoration(labelText: 'SMS code')),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submit, child: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(_sent ? 'Verify and continue' : 'Send OTP')),
        if (_sent) TextButton(onPressed: _busy ? null : () => setState(() { _sent = false; _otp.clear(); _error = null; }), child: const Text('Change mobile number')),
      ]),
    ),
  ))));
}

class _RoleGate extends StatefulWidget {
  const _RoleGate({required this.client, required this.user});
  final SupabaseClient client;
  final User user;
  @override
  State<_RoleGate> createState() => _RoleGateState();
}
class _RoleGateState extends State<_RoleGate> {
  late Future<bool> _access;
  @override
  void initState() { super.initState(); _access = _check(); }
  Future<bool> _check() async {
    final rows = await widget.client.from('user_roles').select('role').eq('user_id', widget.user.id).eq('role', 'driver_partner').limit(1);
    return rows.isNotEmpty;
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(future: _access, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (snapshot.hasError || snapshot.data != true) return Scaffold(appBar: AppBar(title: const Text('Alteo Driver')),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_outline, size: 48), const SizedBox(height: 12),
        const Text('Driver access is not approved for this account.', textAlign: TextAlign.center),
        const SizedBox(height: 12), OutlinedButton(onPressed: () async => widget.client.auth.signOut(), child: const Text('Sign out')),
      ]))));
    return _DriverHome(client: widget.client, user: widget.user);
  });
}

class _DriverHome extends StatefulWidget {
  const _DriverHome({required this.client, required this.user});
  final SupabaseClient client;
  final User user;
  @override
  State<_DriverHome> createState() => _DriverHomeState();
}
class _DriverHomeState extends State<_DriverHome> {
  late Future<List<Map<String, dynamic>>> _rides;
  late Future<List<Map<String, dynamic>>> _earnings;
  bool _busy = false;
  @override
  void initState() { super.initState(); _refresh(); }
  void _refresh() {
    _rides = widget.client.from('rides')
      .select('id,status,pickup_label,destination_label,estimated_distance_m,fare_minor,currency,created_at')
      .eq('driver_id', widget.user.id).order('created_at', ascending: false).limit(100)
      .then((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
    _earnings = widget.client.from('driver_earnings')
      .select('id,amount_minor,currency,status,created_at').eq('driver_id', widget.user.id)
      .order('created_at', ascending: false).limit(100)
      .then((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }
  Future<void> _action(Map<String, dynamic> ride, String action) async {
    setState(() => _busy = true);
    try {
      await widget.client.rpc('driver_update_ride_status', params: {'p_ride_id': ride['id'], 'p_action': action});
      if (mounted) {
        setState(_refresh);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ride updated: ' + action.replaceAll('_', ' '))));
      }
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update this ride.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My trips', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: () => setState(_refresh), icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'Sign out', onPressed: () async => widget.client.auth.signOut(), icon: const Icon(Icons.logout)),
      ]),
    body: RefreshIndicator(onRefresh: () async { setState(_refresh); await Future.wait([_rides, _earnings]); },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Assigned trips', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6), const Text('Trips become visible after Alteo operations assigns a driver.'),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(future: _rides, builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          if (snapshot.hasError) return const _Notice(title: 'Trips unavailable', detail: 'Check connection and access permissions, then refresh.');
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) return const _Notice(title: 'No trips assigned', detail: 'Contact Alteo operations if you are expecting a trip.');
          return Column(children: rows.map((ride) {
            final status = ride['status']?.toString() ?? 'requested';
            final closed = ['completed','cancelled'].contains(status);
            final distance = ((ride['estimated_distance_m'] as num?)?.toInt() ?? 0) / 1000;
            final fare = ((ride['fare_minor'] as num?)?.toInt() ?? 0) / 100;
            return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.directions_car_outlined, color: Color(0xFF176B57)), const SizedBox(width: 8),
                Expanded(child: Text('Trip ' + ride['id'].toString().substring(0, 8).toUpperCase(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Chip(label: Text(status.replaceAll('_', ' '))),
              ]),
              const SizedBox(height: 8),
              Text('Pickup: ' + ride['pickup_label'].toString()),
              const SizedBox(height: 4), Text('Destination: ' + ride['destination_label'].toString()),
              const SizedBox(height: 6), Text('Estimated distance: ' + distance.toStringAsFixed(1) + ' km • Fare: ₹' + fare.toStringAsFixed(2)),
              if (!closed) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  if (status == 'requested') FilledButton.tonal(onPressed: _busy ? null : () => _action(ride, 'accept'), child: const Text('Accept')),
                  if (status == 'accepted') FilledButton(onPressed: _busy ? null : () => _action(ride, 'arrived'), child: const Text('Arrived')),
                  if (status == 'arrived') FilledButton(onPressed: _busy ? null : () => _action(ride, 'start'), child: const Text('Start trip')),
                  if (status == 'in_progress') FilledButton(onPressed: _busy ? null : () => _action(ride, 'complete'), child: const Text('Complete trip')),
                  if (['requested','accepted','arrived'].contains(status)) TextButton(onPressed: _busy ? null : () => _action(ride, 'cancel'), child: const Text('Cancel')),
                ]),
              ],
            ])));
          }).toList());
        }),
        const SizedBox(height: 22), Text('Earnings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        FutureBuilder<List<Map<String, dynamic>>>(future: _earnings, builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LinearProgressIndicator();
          if (snapshot.hasError) return const Text('Earnings unavailable.');
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) return const Text('Earnings appear when completed trips are reconciled.');
          final total = rows.fold<int>(0, (sum, row) => sum + ((row['amount_minor'] as num?)?.toInt() ?? 0));
          return Card(child: ListTile(leading: const Icon(Icons.currency_rupee, color: Color(0xFF176B57)),
            title: Text('Recorded earnings: ₹' + (total / 100).toStringAsFixed(2)),
            subtitle: Text(rows.length.toString() + ' earning records; settlement is separate.')));
        }),
      ]),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.detail});
  final String title, detail;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(24), child: Column(children: [
    const Icon(Icons.inbox_outlined, size: 42), const SizedBox(height: 10),
    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    const SizedBox(height: 6), Text(detail, textAlign: TextAlign.center),
  ]));
}
