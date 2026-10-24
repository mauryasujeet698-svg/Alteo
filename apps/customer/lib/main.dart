import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'src/config/app_config.dart';
import 'src/services/mapbox_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  MapboxService.configure(config.mapboxPublicToken);
  SupabaseClient? client;
  String? error;
  if (config.supabaseUrl.trim().isEmpty || config.supabaseAnonKey.trim().isEmpty) {
    error = 'Build with SUPABASE_URL and SUPABASE_ANON_KEY to connect Alteo.';
  } else {
    try {
      await Supabase.initialize(url: config.supabaseUrl.trim(), anonKey: config.supabaseAnonKey.trim());
      client = Supabase.instance.client;
    } catch (_) { error = 'Supabase initialization failed. Check app configuration.'; }
  }
  runApp(AlteoApp(client: client, configError: error));
}

class AlteoApp extends StatelessWidget {
  const AlteoApp({super.key, required this.client, required this.configError});
  final SupabaseClient? client;
  final String? configError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Alteo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F6),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
    ),
    home: client == null ? ConfigScreen(message: configError ?? 'Configuration needed.') : AuthGate(client: client!),
  );
}

class ConfigScreen extends StatelessWidget {
  const ConfigScreen({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 76),
                const SizedBox(height: 18),
                Text(
                  'Alteo',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text('Everyday services, in one place', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                const Icon(Icons.settings_suggest_outlined, size: 36),
                const SizedBox(height: 10),
                const Text('App configuration needed', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                  'No demo login or fake customer data is used. Configure Supabase before signing in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  User? _user;
  late final StreamSubscription<AuthState> _sub;
  @override
  void initState() {
    super.initState();
    _user = widget.client.auth.currentUser;
    _sub = widget.client.auth.onAuthStateChange.listen((event) {
      if (mounted) setState(() => _user = event.session?.user);
    });
  }
  @override
  void dispose() { _sub.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => _user == null ? PhoneSignIn(client: widget.client) : CustomerShell(client: widget.client, user: _user!);
}

class PhoneSignIn extends StatefulWidget {
  const PhoneSignIn({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<PhoneSignIn> createState() => _PhoneSignInState();
}
class _PhoneSignInState extends State<PhoneSignIn> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _sent = false, _busy = false, _usePhone = false;
  String? _error;
  @override
  void dispose() { _phone.dispose(); _otp.dispose(); super.dispose(); }

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
      if (mounted) setState(() => _error = 'Google sign-in could not start. Check Supabase Google provider and redirect settings.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (!_sent && !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
      setState(() => _error = 'Enter a phone with country code, e.g. +919876543210.');
      return;
    }
    if (_sent && !RegExp(r'^\d{6}$').hasMatch(_otp.text.trim())) {
      setState(() => _error = 'Enter the six-digit SMS code.'); return;
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
      if (mounted) setState(() => _error = 'Sign-in failed. Check SMS provider settings and try again.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Center(child: BrandMark(size: 74)), const SizedBox(height: 16),
        Text('Welcome to Alteo', textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8), const Text('Food, shopping, rides and deliveries — together in one app.', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        if (!_usePhone) ...[
          FilledButton.icon(
            onPressed: _busy ? null : _googleSignIn,
            icon: const Icon(Icons.g_mobiledata, size: 28),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() { _usePhone = true; _error = null; }),
            child: const Text('Use phone number instead'),
          ),
        ] else ...[
          TextField(controller: _phone, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+919876543210', prefixIcon: Icon(Icons.phone_android))),
          if (_sent) ...[
            const SizedBox(height: 12), TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6,
              decoration: const InputDecoration(labelText: 'SMS verification code')),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _submit, child: _busy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_sent ? 'Verify and continue' : 'Continue with mobile')),
          TextButton(onPressed: _busy ? null : () => setState(() { _usePhone = false; _sent = false; _otp.clear(); _error = null; }),
            child: const Text('Back to Google sign-in')),
          const SizedBox(height: 8),
          const Text('Phone sign-in is optional and requires SMS provider setup.', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: CircularProgressIndicator())),
      ])),
  ))));
}
class CartLine {
  CartLine(this.product, [this.quantity = 1]);
  final Map<String, dynamic> product;
  int quantity;
  int get unitMinor => (product['price_minor'] as num?)?.toInt() ?? 0;
  int get totalMinor => unitMinor * quantity;
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key, required this.client, required this.user});
  final SupabaseClient client;
  final User user;
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}
class _CustomerShellState extends State<CustomerShell> {
  int _tab = 0;
  final Map<String, CartLine> _cart = {};
  String _search = '';
  String? _kindFilter;
  late Future<List<Map<String, dynamic>>> _products;
  int get _count => _cart.values.fold(0, (sum, line) => sum + line.quantity);
  int get _total => _cart.values.fold(0, (sum, line) => sum + line.totalMinor);
  @override
  void initState() { super.initState(); _products = _loadProducts(); }

  Future<List<Map<String, dynamic>>> _loadProducts([String search = '', String? kind]) async {
    dynamic query = widget.client.from('seller_products')
      .select('id,name,kind,description,price_minor,currency,image_url,seller_id').eq('status', 'active');
    if (kind != null) {
      query = query.eq('kind', kind);
    } else {
      final safe = search.trim().replaceAll('%', '').replaceAll('_', '');
      if (safe.isNotEmpty) query = query.ilike('name', '%' + safe + '%');
    }
    final rows = await query.order('created_at', ascending: false).limit(24);
    return (rows as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
  void _add(Map<String, dynamic> product) {
    final id = product['id']?.toString();
    if (id == null) return;
    setState(() {
      final line = _cart[id];
      if (line == null) { _cart[id] = CartLine(product); }
      else if (line.quantity < 99) { line.quantity++; }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(product['name'].toString() + ' added to cart'), duration: const Duration(milliseconds: 900)));
  }
  void _quantity(String id, int delta) {
    setState(() {
      final line = _cart[id];
      if (line == null) return;
      line.quantity += delta;
      if (line.quantity <= 0) _cart.remove(id);
    });
  }
  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final address = await showDialog<Map<String, String>>(context: context, builder: (_) => const AddressDialog());
    if (address == null || !mounted) return;
    final items = _cart.entries.map((e) => {'product_id': e.key, 'quantity': e.value.quantity}).toList();
    final key = DateTime.now().microsecondsSinceEpoch.toString() + '-' + Random.secure().nextInt(1 << 32).toString();
    try {
      final orderId = await widget.client.rpc('create_customer_order', params: {
        'p_items': items, 'p_delivery_address': address, 'p_idempotency_key': key, 'p_delivery_fee_minor': 0,
      });
      if (!mounted) return;
      setState(() { _cart.clear(); _tab = 1; });
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Order created'),
        content: Text('Reference: ' + orderId.toString() + '\n\nPayment is pending. Configure a payment provider before fulfilling paid orders.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('View orders'))],
      ));
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create your order. Check your connection and try again.')));
    }
  }
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(client: widget.client, user: widget.user, products: _products, search: _search,
        onSearch: (v) => setState(() { _search = v; _kindFilter = null; _products = _loadProducts(v); }),
        onRefresh: () => setState(() => _products = _loadProducts(_search, _kindFilter)), onAdd: _add, onService: _service),
      ActivityPage(client: widget.client, user: widget.user),
      CartPage(cart: _cart, totalMinor: _total, onQuantity: _quantity, onCheckout: _checkout),
      AccountPage(user: widget.user, client: widget.client),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: NavigationBar(selectedIndex: _tab, onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Orders'),
          NavigationDestination(icon: Badge(isLabelVisible: _count > 0, label: Text(_count.toString()), child: const Icon(Icons.shopping_bag_outlined)),
            selectedIcon: const Icon(Icons.shopping_bag), label: 'Cart'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ]),
    );
  }
  void _service(String name) {
    if (name == 'Shopping' || name == 'Food' || name == 'Quick') {
      final kind = name == 'Shopping' ? 'shopping' : name == 'Food' ? 'food' : 'quick';
      setState(() { _tab = 0; _search = ''; _kindFilter = kind; _products = _loadProducts('', kind); });
      return;
    }
    if (name == 'Rides' || name == 'Parcels') {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BookingPage(client: widget.client, service: name == 'Rides' ? 'ride' : 'parcel'),
      ));
      return;
    }
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8),
        const Text('Offers managed by Alteo appear on the home screen when an admin publishes them.'),
        const SizedBox(height: 14), OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ]),
    ));
  }
}

class BookingPage extends StatefulWidget {
  const BookingPage({super.key, required this.client, required this.service});
  final SupabaseClient client;
  final String service; // ride or parcel

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  PlaceSuggestion? _pickup;
  PlaceSuggestion? _destination;
  MapboxMap? _map;
  final _description = TextEditingController();
  final _area = TextEditingController(text: 'DEFAULT');
  bool _busy = false;
  String? _error;
  String? _bookingId;
  int? _fareMinor;

  @override
  void dispose() {
    _description.dispose();
    _area.dispose();
    super.dispose();
  }

  void _selectPlace(PlaceSuggestion value, {required bool pickup}) {
    setState(() {
      if (pickup) { _pickup = value; } else { _destination = value; }
      _bookingId = null;
    });
    final map = _map;
    if (map != null) {
      map.flyTo(
        CameraOptions(center: Point(coordinates: Position(value.longitude, value.latitude)), zoom: 13),
        MapAnimationOptions(duration: 650),
      );
    }
  }

  Future<void> _submit() async {
    if (_pickup == null || _destination == null) {
      setState(() => _error = 'Choose both pickup and destination from the map search suggestions.');
      return;
    }
    if (widget.service == 'parcel' && _description.text.trim().length < 2) {
      setState(() => _error = 'Describe the parcel contents briefly.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final key = DateTime.now().microsecondsSinceEpoch.toString() + '-' + Random.secure().nextInt(1 << 32).toString();
    try {
      dynamic id;
      if (widget.service == 'ride') {
        id = await widget.client.rpc('create_customer_ride', params: {
          'p_pickup_label': _pickup!.label,
          'p_pickup_latitude': _pickup!.latitude,
          'p_pickup_longitude': _pickup!.longitude,
          'p_destination_label': _destination!.label,
          'p_destination_latitude': _destination!.latitude,
          'p_destination_longitude': _destination!.longitude,
          'p_idempotency_key': key,
          'p_area_code': _area.text.trim().isEmpty ? 'DEFAULT' : _area.text.trim().toUpperCase(),
        });
        final row = await widget.client.from('rides').select('fare_minor').eq('id', id).maybeSingle();
        if (mounted) setState(() { _bookingId = id.toString(); _fareMinor = (row?['fare_minor'] as num?)?.toInt(); });
      } else {
        id = await widget.client.rpc('create_customer_parcel', params: {
          'p_pickup_label': _pickup!.label,
          'p_pickup_latitude': _pickup!.latitude,
          'p_pickup_longitude': _pickup!.longitude,
          'p_destination_label': _destination!.label,
          'p_destination_latitude': _destination!.latitude,
          'p_destination_longitude': _destination!.longitude,
          'p_item_description': _description.text.trim(),
          'p_idempotency_key': key,
          'p_area_code': _area.text.trim().isEmpty ? 'DEFAULT' : _area.text.trim().toUpperCase(),
        });
        final row = await widget.client.from('delivery_jobs').select('fare_minor').eq('id', id).maybeSingle();
        if (mounted) setState(() { _bookingId = id.toString(); _fareMinor = (row?['fare_minor'] as num?)?.toInt(); });
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Booking failed. Check that Mapbox, service availability and pricing are configured.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRide = widget.service == 'ride';
    return Scaffold(
      appBar: AppBar(title: Text(isRide ? 'Book a ride' : 'Send a parcel')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: const Color(0xFFE4F2EB), borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Icon(isRide ? Icons.directions_car : Icons.local_shipping, size: 36, color: const Color(0xFF176B57)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isRide ? 'Where are you going?' : 'Where should we collect and deliver?',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Search Indian addresses or places and select a result.'),
                ])),
              ]),
            ),
            const SizedBox(height: 18),
            if (MapboxService.isConfigured) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 235,
                  child: MapWidget(
                    key: const ValueKey('alteo-booking-map'),
                    cameraOptions: CameraOptions(
                      center: Point(coordinates: Position(78.9629, 20.5937)),
                      zoom: 4.6,
                    ),
                    onMapCreated: (map) { _map = map; },
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (!MapboxService.isConfigured)
              const _BookingNotice(
                text: 'Map search is not configured. Add a restricted public Mapbox token to the build configuration before booking.',
              ),
            const Text('Pickup', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _PlacePickerField(
              key: const ValueKey('pickup-place'),
              label: 'Search pickup address',
              icon: Icons.trip_origin,
              onSelected: (value) => _selectPlace(value, pickup: true),
            ),
            const SizedBox(height: 16),
            const Text('Destination', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _PlacePickerField(
              key: const ValueKey('destination-place'),
              label: 'Search destination address',
              icon: Icons.location_on_outlined,
              onSelected: (value) => _selectPlace(value, pickup: false),
            ),
            if (!isRide) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'What are you sending?', hintText: 'Documents, small package, etc.'),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _area,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Service area code', helperText: 'Use the code enabled by Alteo operations; DEFAULT is a fallback area.'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy || _bookingId != null || !MapboxService.isConfigured ? null : _submit,
              icon: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
              label: Text(_busy ? 'Submitting…' : isRide ? 'Request ride' : 'Request parcel pickup'),
            ),
            if (_bookingId != null) ...[
              const SizedBox(height: 18),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle, color: Color(0xFF176B57), size: 32),
                const SizedBox(height: 8),
                Text(isRide ? 'Ride request created' : 'Parcel request created', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Reference: ' + _bookingId!),
                if (_fareMinor != null) Text('Estimated fare: ₹' + (_fareMinor! / 100).toStringAsFixed(2)),
                const SizedBox(height: 6),
                const Text('The request is recorded. An eligible partner must be assigned before fulfilment; routing-based fare estimates need verification against the actual road route.'),
              ]))),
            ],
            const SizedBox(height: 10),
            const Text('Bookings depend on active service-area rules and pricing. No payment is collected in this screen.',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PlacePickerField extends StatelessWidget {
  const _PlacePickerField({super.key, required this.label, required this.icon, required this.onSelected});
  final String label;
  final IconData icon;
  final ValueChanged<PlaceSuggestion> onSelected;

  @override
  Widget build(BuildContext context) => Autocomplete<PlaceSuggestion>(
    displayStringForOption: (option) => option.label,
    optionsBuilder: (value) async {
      if (value.text.trim().length < 3 || !MapboxService.isConfigured) return const <PlaceSuggestion>[];
      try {
        return await MapboxService.searchPlaces(value.text);
      } catch (_) {
        return const <PlaceSuggestion>[];
      }
    },
    onSelected: onSelected,
    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), helperText: 'Enter at least 3 characters and choose a suggestion.'),
      onSubmitted: (_) => onFieldSubmitted(),
    ),
    optionsViewBuilder: (context, onSelectedOption, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250, maxWidth: 500),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              return ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(option.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => onSelectedOption(option),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _BookingNotice extends StatelessWidget {
  const _BookingNotice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error)),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.client, required this.user, required this.products, required this.search,
    required this.onSearch, required this.onRefresh, required this.onAdd, required this.onService});
  final SupabaseClient client;
  final User user;
  final Future<List<Map<String, dynamic>>> products;
  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onRefresh;
  final ValueChanged<Map<String, dynamic>> onAdd;
  final ValueChanged<String> onService;

  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh: () async => onRefresh(),
    child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Row(children: [
        const BrandMark(size: 44), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hello, ' + _firstName(user), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const Text('What do you need today?', style: TextStyle(color: Colors.black54)),
        ])),
        IconButton(tooltip: 'Refresh', onPressed: onRefresh, icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 18),
      TextField(key: const ValueKey('product-search'), textInputAction: TextInputAction.search, onSubmitted: onSearch,
        decoration: InputDecoration(hintText: 'Search food, groceries and products', prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: () => onSearch(''), icon: const Icon(Icons.close)))),
      const SizedBox(height: 18),
      LivePromotions(client: client),
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF176B57), Color(0xFF31977D)])),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ALTEO EVERYDAY', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            const SizedBox(height: 8),
            Text('One app. More possibilities.', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6), const Text('Shop local, order food and get things moving.', style: TextStyle(color: Colors.white)),
          ])),
          const SizedBox(width: 8), const Icon(Icons.local_mall_outlined, size: 54, color: Colors.white),
        ])),
      const SizedBox(height: 22),
      Text('Explore services', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3,
        mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .93, children: [
          ServiceTile(label: 'Food', detail: 'Local meals', icon: Icons.lunch_dining, color: const Color(0xFFFFE6D6), onTap: () => onService('Food')),
          ServiceTile(label: 'Shopping', detail: 'Nearby shops', icon: Icons.shopping_basket, color: const Color(0xFFDDF2E9), onTap: () => onService('Shopping')),
          ServiceTile(label: 'Quick', detail: 'Daily needs', icon: Icons.bolt, color: const Color(0xFFFFF0B9), onTap: () => onService('Quick')),
          ServiceTile(label: 'Rides', detail: 'Go places', icon: Icons.directions_car, color: const Color(0xFFDCEAFF), onTap: () => onService('Rides')),
          ServiceTile(label: 'Parcels', detail: 'Send items', icon: Icons.local_shipping, color: const Color(0xFFECE2FF), onTap: () => onService('Parcels')),
          ServiceTile(label: 'Offers', detail: 'Save more', icon: Icons.local_offer, color: const Color(0xFFFFE1E7), onTap: () => onService('Offers')),
        ]),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: Text(search.isEmpty ? 'Available products' : 'Search results',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        TextButton(onPressed: onRefresh, child: const Text('Refresh')),
      ]),
      FutureBuilder<List<Map<String, dynamic>>>(future: products, builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()));
        if (snapshot.hasError) return EmptyPanel(icon: Icons.cloud_off_outlined, title: 'Could not load products',
          subtitle: 'Check your connection, seller catalogue and Supabase policies.', actionLabel: 'Try again', onAction: onRefresh);
        final values = snapshot.data ?? [];
        if (values.isEmpty) return const EmptyPanel(icon: Icons.storefront_outlined, title: 'Your local catalogue is getting ready',
          subtitle: 'Approved sellers and active products will appear here. Alteo does not display fake listings.');
        return ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: values.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) {
            final p = values[index];
            final price = ((p['price_minor'] as num?)?.toInt() ?? 0) / 100;
            return Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              leading: Container(width: 52, height: 52, decoration: BoxDecoration(color: const Color(0xFFE8F3EE), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF176B57))),
              title: Text(p['name']?.toString() ?? 'Product', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(_capitalize(p['kind']?.toString() ?? 'item') + ' • ₹' + price.toStringAsFixed(2)),
              trailing: IconButton.filledTonal(tooltip: 'Add to cart', onPressed: () => onAdd(p), icon: const Icon(Icons.add))));
          });
      }),
      const SizedBox(height: 18), const Text('Availability and prices depend on your launch area.', style: TextStyle(color: Colors.black54, fontSize: 12)),
    ]));
}

class LivePromotions extends StatefulWidget {
  const LivePromotions({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<LivePromotions> createState() => _LivePromotionsState();
}
class _LivePromotionsState extends State<LivePromotions> {
  late Future<List<Map<String, dynamic>>> _banners;
  late Future<List<Map<String, dynamic>>> _offers;
  @override
  void initState() {
    super.initState();
    _load();
  }
  void _load() {
    _banners = widget.client.from('app_banners').select('id,title,subtitle,image_url,action_type,action_value')
      .eq('active', true).order('priority').limit(5)
      .then((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
    _offers = widget.client.from('offers').select('id,code,title,description,service,discount_type,discount_value')
      .eq('active', true).order('created_at', ascending: false).limit(10)
      .then((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    FutureBuilder<List<Map<String, dynamic>>>(future: _banners, builder: (context, snapshot) {
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) return const SizedBox.shrink();
      return SizedBox(height: 118, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10), itemBuilder: (context, index) {
          final row = rows[index];
          return Container(width: 285, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [Color(0xFF176B57), Color(0xFF31977D)])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(row['title']?.toString() ?? 'Alteo offer', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
              if ((row['subtitle']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(row['subtitle'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
              ],
            ]));
        }));
    }),
    FutureBuilder<List<Map<String, dynamic>>>(future: _offers, builder: (context, snapshot) {
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 14),
        Text('Offers for you', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SizedBox(height: 76, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (context, index) {
            final row = rows[index];
            final value = row['discount_value']?.toString() ?? '';
            final type = row['discount_type']?.toString() == 'percent' ? '% off' : 'paise off';
            return Container(width: 210, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF0B9), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row['title']?.toString() ?? 'Offer', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
                Text((row['code']?.toString() ?? '') + '  •  ' + value + ' ' + type,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              ]));
          })),
      ]);
    }),
    const SizedBox(height: 4),
  ]);
}

class ServiceTile extends StatelessWidget {
  const ServiceTile({super.key, required this.label, required this.detail, required this.icon, required this.color, required this.onTap});
  final String label, detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18),
    child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 29, color: const Color(0xFF24372F)), const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3),
        Text(detail, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ])));
}

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.client, required this.user});
  final SupabaseClient client;
  final User user;

  @override
  Widget build(BuildContext context) => DefaultTabController(length: 3, child: Scaffold(
    appBar: AppBar(title: const Text('Your activity'), bottom: const TabBar(tabs: [
      Tab(text: 'Orders'), Tab(text: 'Rides'), Tab(text: 'Parcels'),
    ])),
    body: TabBarView(children: [
      _ActivityList(client: client, user: user, type: 'orders'),
      _ActivityList(client: client, user: user, type: 'rides'),
      _ActivityList(client: client, user: user, type: 'parcels'),
    ]),
  ));
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.client, required this.user, required this.type});
  final SupabaseClient client;
  final User user;
  final String type;

  Future<List<Map<String, dynamic>>> _load() async {
    if (type == 'orders') {
      final rows = await client.from('orders').select('id,status,payment_status,total_minor,currency,created_at')
        .eq('customer_id', user.id).order('created_at', ascending: false).limit(50);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }
    if (type == 'rides') {
      final rows = await client.from('rides').select('id,status,pickup_label,destination_label,fare_minor,estimated_distance_m,created_at')
        .eq('customer_id', user.id).order('created_at', ascending: false).limit(50);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }
    final rows = await client.from('delivery_jobs').select('id,status,pickup_label,destination_label,item_description,fare_minor,created_at')
      .eq('customer_id', user.id).eq('job_type', 'parcel').order('created_at', ascending: false).limit(50);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _load(),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return const _ActivityMessage(title: 'Activity unavailable', subtitle: 'Check your connection and refresh.');
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) {
        final title = type == 'orders' ? 'No orders yet' : type == 'rides' ? 'No rides yet' : 'No parcels yet';
        return _ActivityMessage(title: title, subtitle: 'Your ' + type + ' will appear here when you book them.');
      }
      return RefreshIndicator(
        onRefresh: () async {},
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final row = rows[i];
            final fare = ((row['total_minor'] ?? row['fare_minor']) as num?)?.toInt() ?? 0;
            final amount = (fare / 100).toStringAsFixed(2);
            final id = row['id'].toString();
            if (type == 'orders') {
              return Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
                title: Text('Order ' + id.substring(0, 8).toUpperCase()),
                subtitle: Text(_capitalize((row['status'] ?? '').toString().replaceAll('_', ' ')) + ' • Payment: ' + _capitalize((row['payment_status'] ?? '').toString())),
                trailing: Text('₹' + amount, style: const TextStyle(fontWeight: FontWeight.w800)),
              ));
            }
            return Card(child: ListTile(
              leading: Icon(type == 'rides' ? Icons.directions_car_outlined : Icons.local_shipping_outlined, color: const Color(0xFF176B57)),
              title: Text((type == 'rides' ? 'Ride ' : 'Parcel ') + id.substring(0, 8).toUpperCase()),
              subtitle: Text(_capitalize((row['status'] ?? '').toString().replaceAll('_', ' ')) +
                '\nFrom: ' + (row['pickup_label']?.toString() ?? '—') +
                '\nTo: ' + (row['destination_label']?.toString() ?? '—') +
                ((row['item_description']?.toString() ?? '').isNotEmpty ? '\nItems: ' + row['item_description'].toString() : '')),
              isThreeLine: true,
              trailing: Text('₹' + amount, style: const TextStyle(fontWeight: FontWeight.w800)),
            ));
          },
        ),
      );
    },
  );
}

class _ActivityMessage extends StatelessWidget {
  const _ActivityMessage({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.history, size: 46, color: Color(0xFF176B57)),
      const SizedBox(height: 12), Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
    ],
  )));
}


class CartPage extends StatelessWidget {
  const CartPage({super.key, required this.cart, required this.totalMinor, required this.onQuantity, required this.onCheckout});
  final Map<String, CartLine> cart;
  final int totalMinor;
  final void Function(String, int) onQuantity;
  final Future<void> Function() onCheckout;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Your cart')),
    body: cart.isEmpty
      ? const EmptyPanel(icon: Icons.shopping_bag_outlined, title: 'Your cart is empty', subtitle: 'Add products from the home screen to begin.')
      : Column(children: [
        Expanded(child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: cart.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = cart.entries.elementAt(index);
            final line = entry.value;
            return Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
              const CircleAvatar(child: Icon(Icons.inventory_2_outlined)), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(line.product['name']?.toString() ?? 'Product', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('₹' + (line.totalMinor / 100).toStringAsFixed(2)),
              ])),
              IconButton(onPressed: () => onQuantity(entry.key, -1), icon: const Icon(Icons.remove_circle_outline)),
              Text(line.quantity.toString()),
              IconButton(onPressed: () => onQuantity(entry.key, 1), icon: const Icon(Icons.add_circle_outline)),
            ])));
          })),
        Container(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), decoration: const BoxDecoration(color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE8ECE8)))),
          child: Column(children: [
            Row(children: [const Expanded(child: Text('Subtotal')), Text('₹' + (totalMinor / 100).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w800))]),
            const SizedBox(height: 5), const Align(alignment: Alignment.centerLeft, child: Text('Delivery fee is confirmed for your area.', style: TextStyle(fontSize: 12, color: Colors.black54))),
            const SizedBox(height: 14), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onCheckout, icon: const Icon(Icons.lock_outline), label: const Text('Continue to checkout'))),
          ])),
      ]));
}

class AddressDialog extends StatefulWidget {
  const AddressDialog({super.key});
  @override
  State<AddressDialog> createState() => _AddressDialogState();
}
class _AddressDialogState extends State<AddressDialog> {
  final _name = TextEditingController(), _phone = TextEditingController(), _line = TextEditingController();
  final _city = TextEditingController(), _state = TextEditingController(text: 'Uttar Pradesh'), _pin = TextEditingController();
  final _area = TextEditingController(text: 'DEFAULT');
  String? _error;
  @override
  void dispose() { _name.dispose(); _phone.dispose(); _line.dispose(); _city.dispose(); _state.dispose(); _pin.dispose(); _area.dispose(); super.dispose(); }
  void _submit() {
    final address = {'recipient_name': _name.text.trim(), 'phone': _phone.text.trim(), 'address_line1': _line.text.trim(),
      'city': _city.text.trim(), 'state': _state.text.trim(), 'postal_code': _pin.text.trim(), 'area_code': _area.text.trim().isEmpty ? 'DEFAULT' : _area.text.trim().toUpperCase()};
    if (address.values.any((v) => v.isEmpty) || address['recipient_name']!.length < 2 || address['phone']!.length < 8 ||
        address['address_line1']!.length < 3 || address['postal_code']!.length < 5) {
      setState(() => _error = 'Complete all fields and check the phone number and PIN code.'); return;
    }
    Navigator.pop(context, address);
  }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('Delivery address'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Recipient name')),
      const SizedBox(height: 8), TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
      const SizedBox(height: 8), TextField(controller: _line, decoration: const InputDecoration(labelText: 'House / street / village')),
      const SizedBox(height: 8), TextField(controller: _city, decoration: const InputDecoration(labelText: 'City / district')),
      const SizedBox(height: 8), TextField(controller: _state, decoration: const InputDecoration(labelText: 'State')),
      const SizedBox(height: 8), TextField(controller: _pin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN code')),
      const SizedBox(height: 8), TextField(controller: _area, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Service area code', helperText: 'Use the area code enabled by Alteo admin.')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _submit, child: const Text('Save address'))]);
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.user, required this.client});
  final User user;
  final SupabaseClient client;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Account')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
        const CircleAvatar(radius: 28, child: Icon(Icons.person_outline, size: 30)), const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_firstName(user), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(user.phone ?? user.email ?? 'Alteo customer'),
        ])),
      ]))),
      const SizedBox(height: 10),
      const Card(child: Column(children: [
        ListTile(leading: Icon(Icons.location_on_outlined), title: Text('Delivery addresses'), subtitle: Text('Choose an address at checkout.')),
        Divider(height: 1),
        ListTile(leading: Icon(Icons.help_outline), title: Text('Help and support'), subtitle: Text('Support options will be enabled for your launch area.')),
        Divider(height: 1),
        ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('Privacy and security'), subtitle: Text('Account data is protected by backend access policies.')),
      ])),
      const SizedBox(height: 18),
      OutlinedButton.icon(onPressed: () async => client.auth.signOut(), icon: const Icon(Icons.logout), label: const Text('Sign out')),
      const SizedBox(height: 8),
      const Center(child: Text('Alteo • Everyday services', style: TextStyle(color: Colors.black54, fontSize: 12))),
    ]));
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.icon, required this.title, required this.subtitle, this.actionLabel, this.onAction});
  final IconData icon;
  final String title, subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(24, 38, 24, 38),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 46, color: const Color(0xFF176B57)), const SizedBox(height: 12),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
      if (actionLabel != null && onAction != null) ...[const SizedBox(height: 14), OutlinedButton(onPressed: onAction, child: Text(actionLabel!))],
    ])));
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size,
    decoration: BoxDecoration(color: const Color(0xFF176B57), borderRadius: BorderRadius.circular(size * .28)),
    child: Icon(Icons.all_inclusive, color: Colors.white, size: size * .62));
}
String _firstName(User user) {
  final value = user.userMetadata?['name']?.toString().trim();
  return value != null && value.isNotEmpty ? value.split(' ').first : 'there';
}
String _capitalize(String value) => value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
