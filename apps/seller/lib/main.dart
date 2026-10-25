import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const appName = 'Alteo Seller';
const requiredRole = 'seller';
const redirectScheme = 'com.alteo.seller';
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://nkerkoptbrcadlpxffkn.supabase.co');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_lM6ttzw8KMPH2BNXgMAJVA_3y1h51YD');
final ValueNotifier<ThemeMode> roleThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
final ValueNotifier<String> roleLanguage = ValueNotifier<String>('English');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var backendReady = false;
  try {
    if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
      backendReady = true;
    }
  } catch (_) {
    // Public exploration must work even when auth or backend configuration is unavailable.
  }
  runApp(AlteoRoleApp(backendReady: backendReady));
}

class AlteoRoleApp extends StatelessWidget {
  const AlteoRoleApp({super.key, required this.backendReady});
  final bool backendReady;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: roleThemeMode,
    builder: (context, mode, _) => MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57), brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF43B58A), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF101714),
        useMaterial3: true,
      ),
      home: RoleExplorePage(backendReady: backendReady),
    ),
  );
}

class RoleExplorePage extends StatefulWidget {
  const RoleExplorePage({super.key, required this.backendReady});
  final bool backendReady;
  @override
  State<RoleExplorePage> createState() => _RoleExplorePageState();
}

class _RoleExplorePageState extends State<RoleExplorePage> {
  bool busy = false;
  bool authorized = false;
  int selectedTab = 0;
  bool authSheetOpen = false;
  String? message;
  StreamSubscription<AuthState>? authSubscription;

  @override
  void initState() {
    super.initState();
    try {
      final auth = Supabase.instance.client.auth;
      authSubscription = auth.onAuthStateChange.listen((state) {
        if (state.session != null) {
          _checkRole();
        } else if (mounted && authorized) {
          setState(() => authorized = false);
        }
      });
      if (auth.currentSession != null) _checkRole();
    } catch (_) {
      // Public exploration must work when Supabase is unavailable.
    }
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkRole() async {
    final client = Supabase.instance.client;
    final current = client.auth.currentUser;
    if (current == null) return;
    try {
      final row = await client.from('user_roles')
          .select('role').eq('user_id', current.id).eq('role', requiredRole).maybeSingle();
      if (!mounted) return;
      if (row != null) {
        setState(() { authorized = true; message = 'Access verified.'; });
        if (authSheetOpen && mounted) Navigator.of(context).maybePop();
      } else {
        setState(() {
          authorized = false;
          message = 'Google sign-in succeeded, but this account has not been granted the $requiredRole role yet. Ask the Alteo administrator to approve it.';
        });
        await client.auth.signOut();
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Could not verify your app role. Check the user_roles policy and try again.');
    }
  }

  Future<void> signInWithGoogle() async {
    if (!widget.backendReady) {
      setState(() => message = 'Sign-in is unavailable until the Supabase configuration is restored.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: '$redirectScheme://login-callback/',
      );
      if (mounted) setState(() => message = 'Finish signing in with Google, then return to Alteo.');
    } catch (e) {
      if (!mounted) return;
      final lower = e.toString().toLowerCase();
      setState(() => message = lower.contains('provider is not enabled') || lower.contains('unsupported provider')
          ? 'Google sign-in is not enabled in Supabase yet. Enable Google and add its OAuth credentials in the Supabase dashboard.'
          : 'Google sign-in could not start: ' + e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (authorized) return RoleOperationsPage(onSignOut: () async { await Supabase.instance.client.auth.signOut(); if (mounted) setState(() => authorized = false); });
    return Scaffold(
    appBar: AppBar(
      title: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF176B57), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.explore_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 10),
        const Expanded(child: Text(appName, style: TextStyle(fontWeight: FontWeight.w800))),
      ]),
      actions: [TextButton(onPressed: () => showAuth(context), child: Text(authorized ? 'Access' : 'Sign in'))],
    ),
    body: selectedTab == 0 ? ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF176B57), Color(0xFF2C8B70)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('EXPLORE ALTEO', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.3, fontSize: 11)),
            const SizedBox(height: 10),
            const Text('Your catalogue and orders, connected', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Explore product management, inventory, pricing, order preparation and fulfilment.', style: TextStyle(color: Colors.white, height: 1.45)),
            const SizedBox(height: 12),
            const Text('No account is needed to explore. Sign in only for protected operations.', style: TextStyle(color: Colors.white, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 22),
        const Text('Explore features', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('Open any section to learn how it works. Private records and live operations require authorised access.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
        const SizedBox(height: 12),
        for (final feature in _features)
          Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5EAE5))),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
              leading: CircleAvatar(backgroundColor: const Color(0xFFE3F2E9), child: Icon(feature.icon, color: const Color(0xFF176B57))),
              title: Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(feature.subtitle)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RolePublicFeaturePage(feature: feature, selectedIndex: selectedTab, onNavigate: (index) { if (!mounted) return; setState(() => selectedTab = index); Navigator.of(context).pop(); }, onSignIn: () async { await showAuth(context); if (mounted && authorized) Navigator.of(context).pop(); }))),
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EAE5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(widget.backendReady ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: const Color(0xFF176B57)),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.backendReady
              ? 'Public exploration is available. Live data and protected actions depend on backend permissions and service configuration.'
              : 'Public exploration is available. Sign-in and live data are temporarily unavailable until backend configuration is restored.',
              style: const TextStyle(height: 1.45))),
          ]),
        ),
      ],
    ) : _publicNavContent(_publicNavLabels[selectedTab]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selectedTab,
      onDestinationSelected: (index) => setState(() => selectedTab = index),
      destinations: _publicNavLabels.map((label) => NavigationDestination(
        icon: Icon(_publicNavIcon(label, false)),
        selectedIcon: Icon(_publicNavIcon(label, true)),
        label: label,
      )).toList(),
    ),
  );
  }


  List<String> get _publicNavLabels => switch (requiredRole) {
    'admin' => const ['Home', 'Orders', 'Partners', 'Profile'],
    'driver_partner' => const ['Home', 'Rides', 'Earnings', 'Profile'],
    'delivery_partner' => const ['Home', 'Deliveries', 'Earnings', 'Profile'],
    'seller' => const ['Home', 'Orders', 'Products', 'Profile'],
    'dark_store' => const ['Home', 'Picking', 'Inventory', 'Profile'],
    _ => const ['Home', 'Activity', 'Services', 'Profile'],
  };

  IconData _publicNavIcon(String label, bool selected) => switch (label) {
    'Home' => selected ? Icons.home_rounded : Icons.home_outlined,
    'Orders' => selected ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
    'Partners' => selected ? Icons.groups_rounded : Icons.groups_outlined,
    'Rides' => selected ? Icons.directions_car_filled_rounded : Icons.directions_car_outlined,
    'Deliveries' => selected ? Icons.local_shipping_rounded : Icons.local_shipping_outlined,
    'Earnings' => selected ? Icons.account_balance_wallet_rounded : Icons.account_balance_wallet_outlined,
    'Products' => selected ? Icons.inventory_2_rounded : Icons.inventory_2_outlined,
    'Picking' => selected ? Icons.checklist_rounded : Icons.checklist_outlined,
    'Inventory' => selected ? Icons.warehouse_rounded : Icons.warehouse_outlined,
    _ => selected ? Icons.person_rounded : Icons.person_outline_rounded,
  };

  Widget _publicNavContent(String label) {
    if (label == 'Profile') {
      return ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Profile & preferences', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(appName, style: const TextStyle(color: Color(0xFF68736D))),
        const SizedBox(height: 16),
        Card(elevation: 0, child: ValueListenableBuilder<ThemeMode>(
          valueListenable: roleThemeMode,
          builder: (context, mode, _) => SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark theme'),
            subtitle: const Text('Change the appearance of this app'),
            value: mode == ThemeMode.dark,
            onChanged: (value) => roleThemeMode.value = value ? ThemeMode.dark : ThemeMode.light,
          ),
        )),
        Card(elevation: 0, child: ValueListenableBuilder<String>(
          valueListenable: roleLanguage,
          builder: (context, language, _) => ListTile(
            leading: const Icon(Icons.language_rounded),
            title: const Text('Language'),
            subtitle: Text(language),
            trailing: DropdownButton<String>(
              value: language,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'English', child: Text('English')),
                DropdownMenuItem(value: 'Hindi', child: Text('हिन्दी')),
              ],
              onChanged: (value) { if (value != null) roleLanguage.value = value; },
            ),
          ),
        )),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => showAuth(context),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Sign in with Google'),
        ),
        const SizedBox(height: 8),
        const Text('Sign-in is only needed for protected operations. Public exploration remains available.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
      ]);
    }

    final List<_Feature> selectedFeatures = _features.where((feature) {
      final title = feature.title.toLowerCase();
      switch (label) {
        case 'Orders': return title.contains('order') || title.contains('fulfil') || title.contains('fulfill');
        case 'Partners': return title.contains('partner') || title.contains('assignment') || title.contains('approval');
        case 'Rides': return title.contains('ride') || title.contains('trip') || title.contains('availability') || title.contains('safety');
        case 'Deliveries': return title.contains('delivery') || title.contains('pickup') || title.contains('dispatch') || title.contains('safety');
        case 'Earnings': return title.contains('earning') || title.contains('business') || title.contains('insight') || title.contains('payout');
        case 'Products': return title.contains('catalogue') || title.contains('product') || title.contains('pricing') || title.contains('stock');
        case 'Picking': return title.contains('picking') || title.contains('packing') || title.contains('dispatch');
        case 'Inventory': return title.contains('stock') || title.contains('inventory') || title.contains('catalogue');
        default: return true;
      }
    }).toList();

    final detail = switch (label) {
      'Orders' => 'Review order stages and learn how fulfilment moves from seller to delivery.',
      'Partners' => 'Explore onboarding, role approvals and assignment responsibilities.',
      'Rides' => 'Explore availability, incoming ride requests and trip completion.',
      'Deliveries' => 'Explore assigned jobs, pickup confirmation and delivery milestones.',
      'Earnings' => 'Explore earnings summaries and payout history.',
      'Products' => 'Explore catalogue, pricing, offers and inventory workflows.',
      'Picking' => 'Explore picking, packing and dispatch preparation.',
      'Inventory' => 'Explore stock levels, stock adjustments and availability.',
      _ => 'Explore the tools available in this Alteo app.',
    };
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(label, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text(detail, style: const TextStyle(color: Color(0xFF68736D), height: 1.45)),
      const SizedBox(height: 18),
      if (selectedFeatures.isEmpty)
        const Card(elevation: 0, child: Padding(padding: EdgeInsets.all(18), child: Text('More tools will appear here as the account is set up.')))
      else
        for (final feature in selectedFeatures)
          Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5EAE5))),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: const Color(0xFFE3F2E9), child: Icon(feature.icon, color: const Color(0xFF176B57))),
              title: Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(feature.subtitle)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showModalBottomSheet<void>(
                context: context, showDragHandle: true,
                builder: (context) => SafeArea(child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(feature.icon, color: const Color(0xFF176B57), size: 38),
                    const SizedBox(height: 12),
                    Text(feature.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(feature.detail, style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 12),
                    const Text('Live records appear after the backend is configured and the signed-in account is authorised.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
                  ]),
                )),
              ),
            ),
          ),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () => setState(() => selectedTab = 0), icon: const Icon(Icons.home_outlined), label: const Text('Back to Home')),
    ]);
  }

  Future<void> showAuth(BuildContext context) async {
    authSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(22, 8, 22, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Continue with Google', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Explore the app without an account. Google sign-in is required only for protected operations.', style: TextStyle(height: 1.45)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : () async {
                  setSheetState(() {});
                  await signInWithGoogle();
                  if (mounted) setSheetState(() {});
                },
                icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                label: Text(busy ? 'Connecting to Google…' : 'Sign in / Sign up with Google'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message!, style: const TextStyle(height: 1.4, color: Color(0xFF68736D))),
            ],
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Continue exploring')),
          ]),
        ),
      ),
    );
    authSheetOpen = false;
    if (mounted) setState(() {});
  }
}


class RoleOperationsPage extends StatefulWidget {
  const RoleOperationsPage({super.key, required this.onSignOut});
  final Future<void> Function() onSignOut;
  @override
  State<RoleOperationsPage> createState() => _RoleOperationsPageState();
}

class _RoleOperationsPageState extends State<RoleOperationsPage> {
  SupabaseClient get client => Supabase.instance.client;
  User? get user => client.auth.currentUser;
  late Future<dynamic> metrics;
  late Future<Map<String, dynamic>?> sellerProfile;
  late Future<Map<String, dynamic>?> storeProfile;
  final roleUserId = TextEditingController();
  String grantRole = 'delivery_partner';
  bool partnerOnline = false;
  int selectedTab = 0;

  @override
  void initState() {
    super.initState();
    metrics = requiredRole == 'admin' ? client.rpc('admin_operations_summary') : Future.value(<String, dynamic>{});
    sellerProfile = requiredRole == 'seller' && user != null
      ? client.from('sellers').select('id,status,display_name').eq('owner_id', user!.id).maybeSingle()
      : Future.value(null);
    storeProfile = requiredRole == 'dark_store' && user != null
      ? client.from('dark_stores').select('id,status,name,locality').eq('owner_user_id', user!.id).maybeSingle()
      : Future.value(null);
    if ((requiredRole == 'driver_partner' || requiredRole == 'delivery_partner') && user != null) _loadAvailability();
  }

  @override
  void dispose() {
    roleUserId.dispose();
    super.dispose();
  }

  void notice(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> rpc(String name, Map<String, dynamic> params, String success) async {
    try {
      await client.rpc(name, params: params);
      notice(success);
    } catch (e) {
      notice('Action failed: ' + e.toString());
    }
  }


  Future<void> _loadAvailability() async {
    try {
      final row = await client.from('partner_presence').select('is_online')
        .eq('user_id', user!.id).eq('role', requiredRole).maybeSingle();
      if (mounted) setState(() => partnerOnline = row?['is_online'] as bool? ?? false);
    } catch (_) {}
  }

  Future<void> _setAvailability() async {
    final next = !partnerOnline;
    try {
      await client.rpc('partner_set_availability', params: {
        'p_role': requiredRole,
        'p_area_code': 'DEFAULT',
        'p_is_online': next,
      });
      if (mounted) setState(() => partnerOnline = next);
      notice(next ? 'You are online. Dispatch can assign eligible work.' : 'You are offline.');
    } catch (e) {
      notice('Could not update availability: ' + e.toString());
    }
  }

  PreferredSizeWidget _partnerAppBar(String title) => AppBar(title: Text(title), actions: [
    TextButton.icon(
      onPressed: _setAvailability,
      icon: Icon(partnerOnline ? Icons.toggle_on_rounded : Icons.toggle_off_rounded),
      label: Text(partnerOnline ? 'Online' : 'Go online'),
    ),
    IconButton(tooltip: 'Sign out', onPressed: widget.onSignOut, icon: const Icon(Icons.logout_rounded)),
  ]);

  Future<void> grantUserRole() async {
    final id = roleUserId.text.trim();
    if (id.isEmpty) { notice('Enter the user UUID first.'); return; }
    await rpc('admin_grant_user_role', {'p_user_id': id, 'p_role': grantRole}, 'Role granted.');
    roleUserId.clear();
  }

  Future<void> assignRide(Map<String, dynamic> ride) async {
    final id = TextEditingController();
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Assign driver'),
        content: TextField(controller: id, decoration: const InputDecoration(labelText: 'Approved driver user UUID')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Assign')),
        ],
      ));
      if (ok == true && id.text.trim().isNotEmpty) {
        await rpc('admin_assign_driver', {'p_ride_id': ride['id'], 'p_driver_id': id.text.trim()}, 'Driver assigned. The driver app will receive the ride.');
      }
    } finally { id.dispose(); }
  }

  Future<void> assignDelivery(Map<String, dynamic> job) async {
    final id = TextEditingController();
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Assign delivery partner'),
        content: TextField(controller: id, decoration: const InputDecoration(labelText: 'Approved delivery partner UUID')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Assign')),
        ],
      ));
      if (ok == true && id.text.trim().isNotEmpty) {
        await rpc('admin_assign_delivery_partner', {'p_delivery_job_id': job['id'], 'p_partner_id': id.text.trim()}, 'Delivery partner assigned.');
      }
    } finally { id.dispose(); }
  }

  Future<void> setSellerStatus(Map<String, dynamic> seller, String status) async {
    await rpc('admin_set_seller_status', {'p_seller_id': seller['id'], 'p_status': status}, 'Seller status updated.');
  }

  Future<void> setStoreStatus(Map<String, dynamic> store, String status) async {
    await rpc('admin_set_dark_store_status', {'p_store_id': store['id'], 'p_status': status}, 'Dark-store status updated.');
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return Scaffold(appBar: AppBar(title: const Text('Alteo')), body: const Center(child: Text('Your session ended. Return to sign-in.')));
    final dashboard = switch (requiredRole) {
      'admin' => _adminDashboard(),
      'driver_partner' => _driverDashboard(),
      'delivery_partner' => _deliveryDashboard(),
      'seller' => _sellerDashboard(),
      'dark_store' => _darkStoreDashboard(),
      _ => _emptyPage('Role not supported', 'Contact Alteo support.'),
    };
    return Scaffold(
      body: selectedTab == 0 ? dashboard : _navigationPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) => setState(() => selectedTab = index),
        destinations: _navLabels.map((label) => NavigationDestination(
          icon: Icon(_navIcon(label, false)),
          selectedIcon: Icon(_navIcon(label, true)),
          label: label,
        )).toList(),
      ),
    );
  }

  List<String> get _navLabels => switch (requiredRole) {
    'admin' => const ['Home', 'Orders', 'Partners', 'Profile'],
    'driver_partner' => const ['Home', 'Rides', 'Earnings', 'Profile'],
    'delivery_partner' => const ['Home', 'Deliveries', 'Earnings', 'Profile'],
    'seller' => const ['Home', 'Orders', 'Products', 'Profile'],
    'dark_store' => const ['Home', 'Picking', 'Inventory', 'Profile'],
    _ => const ['Home', 'Work', 'Activity', 'Profile'],
  };

  IconData _navIcon(String label, bool selected) => switch (label) {
    'Home' => selected ? Icons.home_rounded : Icons.home_outlined,
    'Orders' => selected ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
    'Partners' => selected ? Icons.groups_rounded : Icons.groups_outlined,
    'Rides' => selected ? Icons.directions_car_filled_rounded : Icons.directions_car_outlined,
    'Deliveries' => selected ? Icons.local_shipping_rounded : Icons.local_shipping_outlined,
    'Earnings' => selected ? Icons.account_balance_wallet_rounded : Icons.account_balance_wallet_outlined,
    'Products' => selected ? Icons.inventory_2_rounded : Icons.inventory_2_outlined,
    'Picking' => selected ? Icons.checklist_rounded : Icons.checklist_outlined,
    'Inventory' => selected ? Icons.warehouse_rounded : Icons.warehouse_outlined,
    _ => selected ? Icons.person_rounded : Icons.person_outline_rounded,
  };

  Widget _navigationPage() {
    final label = _navLabels[selectedTab];
    if (label == 'Profile') {
      return Scaffold(
        appBar: _appBar('Profile'),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF2C8B70)]), borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Color(0x33FFFFFF), child: Icon(Icons.person_rounded, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.email ?? 'Alteo team member', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Role: $requiredRole', style: const TextStyle(color: Colors.white70)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
          Card(elevation: 0, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [
            const Icon(Icons.palette_outlined), const SizedBox(width: 12), const Expanded(child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.w700))),
            DropdownButton<ThemeMode>(value: roleThemeMode.value, underline: const SizedBox.shrink(), items: const [
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
            ], onChanged: (v) { if (v != null) roleThemeMode.value = v; }),
          ]))),
          Card(elevation: 0, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [
            const Icon(Icons.language_rounded), const SizedBox(width: 12), const Expanded(child: Text('Language', style: TextStyle(fontWeight: FontWeight.w700))),
            ValueListenableBuilder<String>(valueListenable: roleLanguage, builder: (context, language, _) => DropdownButton<String>(value: language, underline: const SizedBox.shrink(), items: const [
              DropdownMenuItem(value: 'English', child: Text('English')),
              DropdownMenuItem(value: 'हिन्दी', child: Text('हिन्दी')),
              DropdownMenuItem(value: 'বাংলা', child: Text('বাংলা')),
              DropdownMenuItem(value: 'தமிழ்', child: Text('தமிழ்')),
            ], onChanged: (v) { if (v != null) roleLanguage.value = v; })),
          ]))),
          Card(elevation: 0, child: ListTile(leading: const Icon(Icons.security_rounded), title: const Text('Access & security'), subtitle: const Text('Google sign-in and role-based access protect live operations.'))),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: widget.onSignOut, icon: const Icon(Icons.logout_rounded), label: const Text('Sign out')),
        ]),
      );
    }
    final descriptions = switch (requiredRole) {
      'admin' => const ['Review customer orders, payment states and service requests.', 'Manage partner access, seller approvals and operational assignments.'],
      'driver_partner' => const ['Review assigned ride requests and update trip status.', 'Review completed trips and earnings when settlement is enabled.'],
      'delivery_partner' => const ['Review assigned deliveries and confirm pickup, transit and delivery.', 'Review completed deliveries and settlement information.'],
      'seller' => const ['Review orders routed to your approved seller account.', 'Maintain published products and available stock.'],
      'dark_store' => const ['Review orders that are ready for picking and dispatch.', 'Maintain stock levels and reconcile inventory.'],
      _ => const ['Explore your role workspace.', 'Review recent activity.'],
    };
    return Scaffold(
      appBar: _appBar(label),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF2C8B70)]), borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ALTEO WORKSPACE', style: TextStyle(color: Colors.white70, letterSpacing: 1.2, fontSize: 10, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Your live operational dashboard remains available from Home.', style: TextStyle(color: Colors.white, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < descriptions.length; i++)
          Card(elevation: 0, margin: const EdgeInsets.only(bottom: 10), child: ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFFE1F2E9), child: Icon(i == 0 ? Icons.task_alt_rounded : Icons.insights_rounded, color: const Color(0xFF176B57))),
            title: Text(i == 0 ? 'Work queue' : 'Activity & insights', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(descriptions[i]),
          )),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: () => setState(() => selectedTab = 0), icon: const Icon(Icons.dashboard_rounded), label: const Text('Open live dashboard')),
      ]),
    );
  }

  PreferredSizeWidget _appBar(String title) => AppBar(title: Text(title), actions: [
    IconButton(tooltip: 'Sign out', onPressed: widget.onSignOut, icon: const Icon(Icons.logout_rounded)),
  ]);

  Widget _adminDashboard() => Scaffold(
    appBar: _appBar('Live operations'),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Operations summary', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      FutureBuilder<dynamic>(future: metrics, builder: (context, s) {
        if (s.hasError) return _error('Summary unavailable. Check admin permissions.');
        if (!s.hasData) return const LinearProgressIndicator();
        final m = Map<String, dynamic>.from(s.data as Map);
        return Wrap(spacing: 8, runSpacing: 8, children: [
          _metric('Orders', m['orders_total']),
          _metric('Paid', m['orders_paid']),
          _metric('Open deliveries', m['delivery_jobs_open']),
          _metric('Open rides', m['rides_open']),
          _metric('Pending sellers', m['sellers_pending']),
        ]);
      }),
      const SizedBox(height: 22),
      const Text('Grant an app role', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      TextField(controller: roleUserId, decoration: const InputDecoration(labelText: 'Existing user UUID', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: grantRole,
        decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'customer', child: Text('Customer')),
          DropdownMenuItem(value: 'driver_partner', child: Text('Driver Partner')),
          DropdownMenuItem(value: 'delivery_partner', child: Text('Delivery Partner')),
          DropdownMenuItem(value: 'seller', child: Text('Seller')),
          DropdownMenuItem(value: 'dark_store', child: Text('Dark Store')),
          DropdownMenuItem(value: 'admin', child: Text('Admin')),
        ],
        onChanged: (v) { if (v != null) setState(() => grantRole = v); },
      ),
      const SizedBox(height: 8),
      FilledButton(onPressed: grantUserRole, child: const Text('Grant role')),
      const SizedBox(height: 24),
      const Text('Orders', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('orders').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Orders unavailable. Check the admin RLS policy.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No orders yet', 'Orders appear after customer checkout is enabled.');
          return Column(children: s.data!.take(25).map((o) => Card(elevation: 0, child: ListTile(
            title: Text('Order ' + _short(o['id']), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Status: ' + (o['status']?.toString() ?? 'unknown') + ' · Payment: ' + (o['payment_status']?.toString() ?? 'unknown') + ' · Total ₹' + (((o['total_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
          ))).toList());
        },
      ),
      const SizedBox(height: 22),
      const Text('Ride requests', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('rides').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Ride requests unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No ride requests', 'New ride requests will appear here.');
          return Column(children: s.data!.take(20).map((r) => Card(elevation: 0, child: ListTile(
            title: Text((r['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (r['destination_label']?.toString() ?? 'Destination')),
            subtitle: Text('Status: ' + (r['status']?.toString() ?? 'unknown') + ' · Fare ₹' + (((r['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
            trailing: IconButton(tooltip: 'Assign driver', icon: const Icon(Icons.person_add_alt_1_rounded), onPressed: () => assignRide(r)),
          ))).toList());
        },
      ),
      const SizedBox(height: 22),
      const Text('Delivery jobs', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('delivery_jobs').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Delivery jobs unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No delivery jobs', 'Delivery jobs will appear when orders or parcels are ready.');
          return Column(children: s.data!.take(20).map((j) => Card(elevation: 0, child: ListTile(
            title: Text((j['job_type']?.toString() ?? 'order').toUpperCase() + ' · ' + _short(j['id'])),
            subtitle: Text('Status: ' + (j['status']?.toString() ?? 'unknown')),
            trailing: IconButton(tooltip: 'Assign delivery partner', icon: const Icon(Icons.local_shipping_rounded), onPressed: () => assignDelivery(j)),
          ))).toList());
        },
      ),
      const SizedBox(height: 22),
      const Text('Seller approvals', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('sellers').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Seller records unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No seller applications', 'Seller applications will appear here.');
          return Column(children: s.data!.take(15).map((seller) => Card(elevation: 0, child: ListTile(
            title: Text(seller['display_name']?.toString() ?? 'Seller'),
            subtitle: Text('Status: ' + (seller['status']?.toString() ?? 'pending')),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Approve seller', onPressed: () => setSellerStatus(seller, 'approved'), icon: const Icon(Icons.check_circle_outline, color: Colors.green)),
              IconButton(tooltip: 'Suspend seller', onPressed: () => setSellerStatus(seller, 'suspended'), icon: const Icon(Icons.block_outlined)),
            ]),
          ))).toList());
        },
      ),
      const SizedBox(height: 22),
      const Text('Dark stores', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('dark_stores').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Dark stores unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No dark stores', 'Create and approve dark stores from the admin tools.');
          return Column(children: s.data!.take(15).map((store) => Card(elevation: 0, child: ListTile(
            title: Text(store['name']?.toString() ?? 'Dark store'),
            subtitle: Text('Status: ' + (store['status']?.toString() ?? 'pending')),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Activate', onPressed: () => setStoreStatus(store, 'active'), icon: const Icon(Icons.check_circle_outline, color: Colors.green)),
              IconButton(tooltip: 'Suspend', onPressed: () => setStoreStatus(store, 'suspended'), icon: const Icon(Icons.block_outlined)),
            ]),
          ))).toList());
        },
      ),
    ]),
  );

  Widget _driverDashboard() => Scaffold(
    appBar: _partnerAppBar('My rides'),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: client.from('rides').stream(primaryKey: ['id']).eq('driver_id', user!.id).order('created_at', ascending: false),
      builder: (context, s) {
        if (s.hasError) return _error('Rides unavailable. Check driver role and RLS.');
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) return _empty('No rides assigned', 'Assigned rides appear here when you are online and eligible for dispatch.');
        return ListView(padding: const EdgeInsets.all(16), children: s.data!.map((r) {
          final status = r['status']?.toString() ?? 'requested';
          final buttons = <Widget>[];
          if (status == 'requested') buttons.add(FilledButton(onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': r['id'], 'p_action': 'accept'}, 'Ride accepted.'), child: const Text('Accept')));
          if (status == 'accepted') buttons.add(FilledButton(onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': r['id'], 'p_action': 'arrived'}, 'Marked arrived.'), child: const Text('Arrived')));
          if (status == 'arrived') buttons.add(FilledButton(onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': r['id'], 'p_action': 'start'}, 'Trip started.'), child: const Text('Start trip')));
          if (status == 'in_progress') buttons.add(FilledButton(onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': r['id'], 'p_action': 'complete'}, 'Trip completed.'), child: const Text('Complete')));
          return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((r['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (r['destination_label']?.toString() ?? 'Destination'), style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6), Text('Status: ' + status + ' · Fare ₹' + (((r['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
            if (buttons.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, children: buttons)),
          ])));
        }).toList());
      },
    ),
  );

  Widget _deliveryDashboard() => Scaffold(
    appBar: _partnerAppBar('My deliveries'),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: client.from('delivery_jobs').stream(primaryKey: ['id']).eq('delivery_partner_id', user!.id).order('created_at', ascending: false),
      builder: (context, s) {
        if (s.hasError) return _error('Deliveries unavailable. Check delivery-partner role and RLS.');
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) return _empty('No deliveries assigned', 'Assigned deliveries and parcels will appear here.');
        return ListView(padding: const EdgeInsets.all(16), children: s.data!.map((j) {
          final status = j['status']?.toString() ?? 'pending';
          final buttons = <Widget>[];
          if (status == 'assigned') {
            buttons.add(OutlinedButton(onPressed: () => rpc('partner_update_delivery_status', {'p_delivery_job_id': j['id'], 'p_action': 'reject'}, 'Delivery declined.'), child: const Text('Decline')));
            buttons.add(FilledButton(onPressed: () => rpc('partner_update_delivery_status', {'p_delivery_job_id': j['id'], 'p_action': 'accept'}, 'Delivery accepted.'), child: const Text('Accept')));
            buttons.add(FilledButton(onPressed: () => rpc('partner_update_delivery_status', {'p_delivery_job_id': j['id'], 'p_action': 'picked_up'}, 'Pickup confirmed.'), child: const Text('Picked up')));
          }
          if (status == 'picked_up') buttons.add(FilledButton(onPressed: () => rpc('partner_update_delivery_status', {'p_delivery_job_id': j['id'], 'p_action': 'in_transit'}, 'Delivery is in transit.'), child: const Text('Start route')));
          if (status == 'in_transit') buttons.add(FilledButton(onPressed: () => rpc('partner_update_delivery_status', {'p_delivery_job_id': j['id'], 'p_action': 'delivered'}, 'Delivery completed.'), child: const Text('Delivered')));
          return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((j['job_type']?.toString() ?? 'order').toUpperCase() + ' · ' + _short(j['id']), style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6), Text('Status: ' + status),
            if ((j['pickup_label']?.toString() ?? '').isNotEmpty) Text('Pickup: ' + j['pickup_label'].toString()),
            if ((j['destination_label']?.toString() ?? '').isNotEmpty) Text('Drop: ' + j['destination_label'].toString()),
            if (buttons.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, runSpacing: 8, children: buttons)),
          ])));
        }).toList());
      },
    ),
  );

  Widget _sellerDashboard() => Scaffold(
    appBar: _appBar('Seller operations'),
    body: FutureBuilder<Map<String, dynamic>?>(future: sellerProfile, builder: (context, profile) {
      if (profile.hasError) return _error('Seller profile unavailable.');
      if (!profile.hasData) return const Center(child: CircularProgressIndicator());
      final seller = profile.data;
      if (seller == null) return ListView(padding: const EdgeInsets.all(20), children: [
        _empty('Seller profile not linked', 'Create a seller application. Admin approval is required before listings and order processing are enabled.'),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _createSellerProfile, icon: const Icon(Icons.storefront_rounded), label: const Text('Request seller profile')),
      ]);
      final sellerId = seller['id'] as String;
      if (seller['status'] != 'approved') return _empty('Seller approval pending', 'Your seller profile status is ' + (seller['status']?.toString() ?? 'pending') + '. Catalogue and order processing unlock after approval.');
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Your catalogue', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: () => _createProduct(sellerId), icon: const Icon(Icons.add_rounded), label: const Text('Add product'))),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: client.from('seller_products').stream(primaryKey: ['id']).eq('seller_id', sellerId).order('created_at', ascending: false),
          builder: (context, s) {
            if (s.hasError) return _error('Catalogue unavailable. Check seller RLS policies.');
            if (!s.hasData) return const LinearProgressIndicator();
            if (s.data!.isEmpty) return _empty('No products yet', 'Product creation is available after catalogue permissions are configured.');
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: client.from('seller_inventory').stream(primaryKey: ['id']).eq('seller_id', sellerId),
              builder: (context, inventorySnapshot) {
                if (inventorySnapshot.hasError) return _error('Seller inventory unavailable.');
                if (!inventorySnapshot.hasData) return const LinearProgressIndicator();
                final stockByProduct = <String, Map<String, dynamic>>{
                  for (final row in inventorySnapshot.data!) (row['product_id'] as String): row,
                };
                return Column(children: s.data!.map((p) {
                  final stock = stockByProduct[p['id']]?['stock_on_hand']?.toString() ?? 'Not set';
                  final reserved = stockByProduct[p['id']]?['reserved_quantity']?.toString() ?? '0';
                  return Card(elevation: 0, child: ListTile(
                    title: Text(p['name']?.toString() ?? 'Product'),
                    subtitle: Text('Status: ' + (p['status']?.toString() ?? 'draft') + ' · ₹' + (((p['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0) + ' · Stock: ' + stock + ' · Reserved: ' + reserved),
                    trailing: IconButton(tooltip: 'Update stock', icon: const Icon(Icons.inventory_2_outlined), onPressed: () => _setSellerStock(sellerId, p)),
                  ));
                }).toList());
              },
            );
          },
        ),
        const SizedBox(height: 22),
        const Text('Orders to fulfil', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: client.from('orders').stream(primaryKey: ['id']).eq('seller_id', sellerId).order('created_at', ascending: false),
          builder: (context, s) {
            if (s.hasError) return _error('Seller orders unavailable.');
            if (!s.hasData) return const LinearProgressIndicator();
            if (s.data!.isEmpty) return _empty('No orders yet', 'Orders routed to your seller account will appear here.');
            return Column(children: s.data!.map((o) {
              final status = o['status']?.toString() ?? 'pending_payment';
              final payment = o['payment_status']?.toString() ?? 'pending';
              final buttons = <Widget>[];
              if (payment == 'paid' && status == 'paid') buttons.add(FilledButton(onPressed: () => rpc('seller_update_order_status', {'p_order_id': o['id'], 'p_action': 'accept'}, 'Order accepted.'), child: const Text('Accept')));
              if (payment == 'paid' && status == 'accepted') buttons.add(FilledButton(onPressed: () => rpc('seller_update_order_status', {'p_order_id': o['id'], 'p_action': 'prepare'}, 'Order preparation started.'), child: const Text('Prepare')));
              if (payment == 'paid' && status == 'preparing') buttons.add(FilledButton(onPressed: () => rpc('seller_update_order_status', {'p_order_id': o['id'], 'p_action': 'ready'}, 'Order ready for pickup.'), child: const Text('Ready for pickup')));
              return Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Order ' + _short(o['id']), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('Status: ' + status + ' · Payment: ' + payment),
                if (payment != 'paid') const Text('Waiting for confirmed payment before fulfilment.', style: TextStyle(color: Color(0xFF68736D))),
                if (buttons.isNotEmpty) Wrap(spacing: 8, children: buttons),
              ])));
            }).toList());
          },
        ),
      ]);
    }),
  );



  Future<void> _createProduct(String sellerId) async {
    final name = TextEditingController();
    final description = TextEditingController();
    final price = TextEditingController();
    String kind = 'shopping';
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add product'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Product name')),
          TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (₹, whole rupees)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: kind,
            decoration: const InputDecoration(labelText: 'Category'),
            items: const [
              DropdownMenuItem(value: 'food', child: Text('Food')),
              DropdownMenuItem(value: 'quick', child: Text('Quick commerce')),
              DropdownMenuItem(value: 'shopping', child: Text('Shopping')),
            ],
            onChanged: (v) { if (v != null) setDialogState(() => kind = v); },
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save draft')),
        ],
      )));
      if (ok != true) return;
      final priceRupees = int.tryParse(price.text.trim());
      if (name.text.trim().isEmpty || priceRupees == null || priceRupees < 1) {
        notice('Enter a product name and a price greater than ₹0.');
        return;
      }
      await client.from('seller_products').insert({
        'seller_id': sellerId,
        'kind': kind,
        'name': name.text.trim(),
        'description': description.text.trim(),
        'price_minor': priceRupees * 100,
        'currency': 'INR',
        'status': 'draft',
      });
      notice('Product saved as a draft. Admin approval is required before it appears in the public catalogue.');
    } catch (e) {
      notice('Could not save product: ' + e.toString());
    } finally {
      name.dispose();
      description.dispose();
      price.dispose();
    }
  }

  Future<void> _createSellerProfile() async {
    final name = TextEditingController();
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Seller application'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Business / shop name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit')),
        ],
      ));
      if (ok != true || user == null) return;
      if (name.text.trim().length < 2) { notice('Enter a valid shop name.'); return; }
      await client.from('sellers').insert({
        'owner_id': user!.id,
        'display_name': name.text.trim(),
        'status': 'pending',
      });
      if (mounted) {
        setState(() {
          sellerProfile = client.from('sellers').select('id,status,display_name').eq('owner_id', user!.id).maybeSingle();
        });
        notice('Seller application submitted for admin review.');
      }
    } catch (e) {
      notice('Could not submit seller application: ' + e.toString());
    } finally {
      name.dispose();
    }
  }

  Future<void> _setSellerStock(String sellerId, Map<String, dynamic> product) async {
    final stock = TextEditingController();
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text('Update stock · ' + (product['name']?.toString() ?? 'Product')),
        content: TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock on hand', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save stock')),
        ],
      ));
      if (ok == true) {
        final quantity = int.tryParse(stock.text.trim());
        if (quantity == null || quantity < 0) { notice('Enter a valid non-negative stock quantity.'); return; }
        await rpc('seller_set_stock', {'p_seller_id': sellerId, 'p_product_id': product['id'], 'p_stock_on_hand': quantity}, 'Stock updated.');
      }
    } finally { stock.dispose(); }
  }

  Widget _darkStoreDashboard() => Scaffold(
    appBar: _appBar('Dark-store inventory'),
    body: FutureBuilder<Map<String, dynamic>?>(future: storeProfile, builder: (context, profile) {
      if (profile.hasError) return _error('Dark-store profile unavailable.');
      if (!profile.hasData) return const Center(child: CircularProgressIndicator());
      final store = profile.data;
      if (store == null) return _empty('Dark store not linked', 'Ask Alteo admin to create and assign a dark store to your account.');
      if (store['status'] != 'active') return _empty('Store not active', 'Your store status is ' + (store['status']?.toString() ?? 'pending') + '. Admin activation is required before stock changes.');
      final storeId = store['id'] as String;
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text(store['name']?.toString() ?? 'Your dark store', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: client.from('dark_store_inventory').stream(primaryKey: ['id']).eq('store_id', storeId).order('updated_at', ascending: false),
          builder: (context, s) {
            if (s.hasError) return _error('Inventory unavailable. Check dark-store RLS policies.');
            if (!s.hasData) return const LinearProgressIndicator();
            if (s.data!.isEmpty) return _empty('No inventory records', 'Add stock records after products are activated in the public catalogue.');
            return Column(children: s.data!.map((item) {
              final product = item['seller_products'] as Map? ?? {};
              return Card(elevation: 0, child: ListTile(
                title: Text(product['name']?.toString() ?? 'Product'),
                subtitle: Text('Stock: ' + (item['stock_on_hand']?.toString() ?? '0') + ' · Reserved: ' + (item['reserved_quantity']?.toString() ?? '0')),
                trailing: IconButton(tooltip: 'Set stock', icon: const Icon(Icons.edit_outlined), onPressed: () => _setStoreStock(storeId, item['product_id'] as String, product['name']?.toString() ?? 'Product', item['stock_on_hand'] as int? ?? 0)),
              ));
            }).toList());
          },
        ),
      ]);
    }),
  );

  Future<void> _setStoreStock(String storeId, String productId, String name, int current) async {
    final stock = TextEditingController(text: current.toString());
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text('Stock · ' + name),
        content: TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock on hand', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save stock')),
        ],
      ));
      if (ok == true) {
        final quantity = int.tryParse(stock.text.trim());
        if (quantity == null || quantity < 0) { notice('Enter a valid non-negative stock quantity.'); return; }
        await rpc('dark_store_set_inventory', {'p_store_id': storeId, 'p_product_id': productId, 'p_stock_on_hand': quantity}, 'Inventory updated.');
      }
    } finally { stock.dispose(); }
  }

  Widget _metric(String title, dynamic value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5EAE5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Color(0xFF68736D), fontSize: 12)), const SizedBox(height: 3), Text((value ?? 0).toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))]),
  );

  Widget _empty(String title, String detail) => Container(
    padding: const EdgeInsets.all(20), margin: const EdgeInsets.only(top: 8, bottom: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EAE5))),
    child: Column(children: [const Icon(Icons.inbox_outlined, size: 36, color: Color(0xFF176B57)), const SizedBox(height: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF68736D), height: 1.4))]),
  );

  Widget _error(String text) => Padding(padding: const EdgeInsets.all(18), child: Text(text, style: const TextStyle(color: Colors.red, height: 1.4)));

  Widget _emptyPage(String title, String detail) => Scaffold(appBar: _appBar(title), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(detail, textAlign: TextAlign.center))));

  String _short(dynamic value) {
    final id = value?.toString() ?? '';
    return id.length > 8 ? id.substring(0, 8) : id.isEmpty ? '—' : id;
  }
}

class _Feature {
  const _Feature(this.title, this.subtitle, this.detail, this.icon);
  final String title, subtitle, detail;
  final IconData icon;
}

const _features = <_Feature>[
  _Feature('Product catalogue', 'Manage items and descriptions', 'Sellers manage their own listings, prices, photos and availability after authorisation.', Icons.inventory_2_rounded),
  _Feature('Inventory', 'Stock and availability', 'Stock changes should be validated by the backend and reflected across customer browsing and dark-store operations.', Icons.inventory_2_rounded),
  _Feature('Incoming orders', 'Prepare and fulfil orders', 'Only orders routed to this seller should be visible; status changes are shared with admin and customers.', Icons.shopping_bag_rounded),
  _Feature('Pricing and offers', 'Keep listings current', 'Authorised sellers update pricing and eligible offers, with validation and audit history.', Icons.sell_rounded),
  _Feature('Business insights', 'Sales and fulfilment summaries', 'See seller-specific summaries when the reporting layer is connected.', Icons.bar_chart_rounded),
];

class RolePublicFeaturePage extends StatelessWidget {
  const RolePublicFeaturePage({super.key, required this.feature, required this.onSignIn, this.selectedIndex = 0, this.onNavigate});
  final _Feature feature;
  final VoidCallback onSignIn;
  final int selectedIndex;
  final ValueChanged<int>? onNavigate;

  List<String> get _navLabels => switch (requiredRole) {
    'admin' => const ['Home', 'Orders', 'Partners', 'Profile'],
    'driver_partner' => const ['Home', 'Rides', 'Earnings', 'Profile'],
    'delivery_partner' => const ['Home', 'Deliveries', 'Earnings', 'Profile'],
    'seller' => const ['Home', 'Orders', 'Products', 'Profile'],
    'dark_store' => const ['Home', 'Picking', 'Inventory', 'Profile'],
    _ => const ['Home', 'Activity', 'Services', 'Profile'],
  };

  IconData _navIcon(String label, bool selected) => switch (label) {
    'Home' => selected ? Icons.home_rounded : Icons.home_outlined,
    'Orders' => selected ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
    'Partners' => selected ? Icons.groups_rounded : Icons.groups_outlined,
    'Rides' => selected ? Icons.directions_car_filled_rounded : Icons.directions_car_outlined,
    'Deliveries' => selected ? Icons.local_shipping_rounded : Icons.local_shipping_outlined,
    'Earnings' => selected ? Icons.account_balance_wallet_rounded : Icons.account_balance_wallet_outlined,
    'Products' => selected ? Icons.inventory_2_rounded : Icons.inventory_2_outlined,
    'Picking' => selected ? Icons.checklist_rounded : Icons.checklist_outlined,
    'Inventory' => selected ? Icons.warehouse_rounded : Icons.warehouse_outlined,
    _ => selected ? Icons.person_rounded : Icons.person_outline_rounded,
  };

  List<String> get sections {
    switch (requiredRole) {
      case 'admin': return const ['Operations summary', 'Orders and service requests', 'Partner assignment', 'Approvals and service settings'];
      case 'driver_partner': return const ['Availability', 'Ride queue', 'Active trip', 'Trip history'];
      case 'delivery_partner': return const ['Availability', 'Delivery queue', 'Pickup and drop-off', 'Delivery history'];
      case 'seller': return const ['Catalogue', 'Inventory and stock', 'Orders to fulfil', 'Store settings'];
      case 'dark_store': return const ['Inventory', 'Picking queue', 'Packing station', 'Dispatch handover'];
      default: return const ['Overview', 'Activity', 'Settings'];
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(feature.title), actions: [
      TextButton(onPressed: onSignIn, child: const Text('Sign in')),
    ]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(22)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.visibility_outlined, color: Color(0xFF176B57), size: 34),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(feature.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(feature.subtitle, style: const TextStyle(color: Color(0xFF365D50))),
          ])),
        ]),
      ),
      const SizedBox(height: 14),
      Text(feature.detail, style: const TextStyle(height: 1.5, color: Color(0xFF68736D))),
      const SizedBox(height: 22),
      const Text('Explore this screen', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      ...sections.map((section) => Card(
        elevation: 0,
        color: Colors.white,
        child: ListTile(
          leading: const Icon(Icons.circle_outlined, color: Color(0xFF176B57)),
          title: Text(section, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('No sample records are shown. Your real data appears here after setup and authorised sign-in.'),
        ),
      )),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: onSignIn, icon: const Icon(Icons.lock_open_rounded), label: const Text('Sign in for protected actions')),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to app overview')),
    ]),
    bottomNavigationBar: onNavigate == null ? null : NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) => onNavigate?.call(index),
      destinations: _navLabels.map((label) => NavigationDestination(
        icon: Icon(_navIcon(label, false)),
        selectedIcon: Icon(_navIcon(label, true)),
        label: label,
      )).toList(),
    ),
  );
}
