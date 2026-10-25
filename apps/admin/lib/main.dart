import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const appName = 'Alteo Admin';
const requiredRole = 'admin';
const redirectScheme = 'com.alteo.admin';
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
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Welcome to ' + appName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            const Text('Explore the tools and workflows available in this app. Sign in with Google for authorised operations.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
          ]),
        ),
        const SizedBox(height: 14),
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
    'admin' => const ['Home', 'Orders', 'Banners', 'Partners', 'Profile'],
    'driver_partner' => const ['Home', 'Rides', 'Earnings', 'Profile'],
    'delivery_partner' => const ['Home', 'Deliveries', 'Earnings', 'Profile'],
    'seller' => const ['Home', 'Orders', 'Products', 'Profile'],
    'dark_store' => const ['Home', 'Picking', 'Inventory', 'Profile'],
    _ => const ['Home', 'Activity', 'Services', 'Profile'],
  };

  IconData _publicNavIcon(String label, bool selected) => switch (label) {
    'Home' => selected ? Icons.home_rounded : Icons.home_outlined,
    'Orders' => selected ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
    'Banners' => selected ? Icons.view_carousel_rounded : Icons.view_carousel_outlined,
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
    if (label == 'Banners') {
      return ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Customer homepage banners', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Create, edit, reorder, publish or unpublish the swipeable carousel shown at the top of the Customer app. Banner changes are delivered through Supabase and do not require an app reinstall.', style: TextStyle(color: Color(0xFF68736D), height: 1.5)),
        const SizedBox(height: 18),
        Card(elevation: 0, child: ListTile(
          leading: const Icon(Icons.view_carousel_rounded, color: Color(0xFF176B57)),
          title: const Text('Homepage banner manager'),
          subtitle: const Text('Sign in as an approved Admin to manage live banners.'),
          trailing: const Icon(Icons.lock_outline_rounded),
        )),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => showAuth(context), icon: const Icon(Icons.login_rounded), label: const Text('Sign in to manage banners')),
      ]);
    }
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


  Future<void> assignOrderToDarkStore(Map<String, dynamic> order) async {
    if ((order['payment_status']?.toString() ?? 'pending') != 'paid') {
      notice('Only paid orders can be assigned to a dark store.');
      return;
    }
    final storeId = TextEditingController();
    try {
      final ok = await showDialog<bool>(context: context, builder: (dc) => AlertDialog(
        title: const Text('Assign order to dark store'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Order ' + _short(order['id'])),
          const SizedBox(height: 10),
          TextField(controller: storeId, decoration: const InputDecoration(labelText: 'Active dark-store UUID', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          const Text('The selected store must be active. The task will appear in its Picking tab.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Assign')),
        ],
      ));
      if (ok != true) return;
      if (storeId.text.trim().isEmpty) { notice('Enter the active dark-store UUID.'); return; }
      await rpc('admin_assign_order_to_dark_store', {'p_order_id': order['id'], 'p_store_id': storeId.text.trim()}, 'Order assigned to the dark store picking queue.');
    } finally {
      storeId.dispose();
    }
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


  Future<void> createDarkStore() async {
    final owner = TextEditingController();
    final name = TextEditingController();
    final locality = TextEditingController();
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Create dark store'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: owner, decoration: const InputDecoration(labelText: 'Owner user UUID')),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Store name')),
          TextField(controller: locality, decoration: const InputDecoration(labelText: 'Locality / service area')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create')),
        ],
      ));
      if (ok == true) {
        if (owner.text.trim().isEmpty || name.text.trim().length < 2) {
          notice('Enter a valid owner UUID and store name.');
          return;
        }
        await rpc('admin_create_dark_store', {
          'p_owner_user_id': owner.text.trim(),
          'p_name': name.text.trim(),
          'p_locality': locality.text.trim(),
        }, 'Dark store created. Activate it after review.');
      }
    } finally {
      owner.dispose();
      name.dispose();
      locality.dispose();
    }
  }

  Future<void> setSellerStatus(Map<String, dynamic> seller, String status) async {
    await rpc('admin_set_seller_status', {'p_seller_id': seller['id'], 'p_status': status}, 'Seller status updated.');
  }


  Future<void> setProductStatus(Map<String, dynamic> product, String status) async {
    await rpc('admin_set_product_status', {'p_product_id': product['id'], 'p_status': status}, 'Product status updated.');
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
    'admin' => const ['Home', 'Orders', 'Banners', 'Partners', 'Profile'],
    'driver_partner' => const ['Home', 'Rides', 'Earnings', 'Profile'],
    'delivery_partner' => const ['Home', 'Deliveries', 'Earnings', 'Profile'],
    'seller' => const ['Home', 'Orders', 'Products', 'Profile'],
    'dark_store' => const ['Home', 'Picking', 'Inventory', 'Profile'],
    _ => const ['Home', 'Work', 'Activity', 'Profile'],
  };

  IconData _navIcon(String label, bool selected) => switch (label) {
    'Home' => selected ? Icons.home_rounded : Icons.home_outlined,
    'Orders' => selected ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
    'Banners' => selected ? Icons.view_carousel_rounded : Icons.view_carousel_outlined,
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
    if (requiredRole == 'admin' && label == 'Banners') {
      return Scaffold(
        appBar: _appBar('Customer homepage banners'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            const Text('Customer homepage banners', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Manage the swipeable Customer home carousel here. Published changes are read live from Supabase; the Customer app does not need reinstalling.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
            const SizedBox(height: 18),
            _bannerManagement(),
          ],
        ),
      );
    }
    if (requiredRole == 'admin' && label == 'Orders') {
      return _adminOrdersPage();
    }
    if (requiredRole == 'admin' && label == 'Partners') {
      return _adminPartnersPage();
    }
    if (requiredRole == 'driver_partner' && label == 'Rides') return _driverDashboard();
    if (requiredRole == 'delivery_partner' && label == 'Deliveries') return _deliveryDashboard();
    if (requiredRole == 'seller' && label == 'Orders') return _sellerOrdersPage();
    if (requiredRole == 'seller' && label == 'Products') return _sellerProductsPage();
    if (requiredRole == 'dark_store' && label == 'Inventory') return _darkStoreDashboard();
    if (requiredRole == 'dark_store' && label == 'Picking') return _darkStorePickingPage();
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


  Future<String> _uploadBannerImage(XFile file) async {
    final signatureResponse = await client.functions.invoke('cloudinary-sign-upload', body: <String, dynamic>{'asset_type': 'banner'});
    if (signatureResponse.status < 200 || signatureResponse.status >= 300) {
      final data = signatureResponse.data;
      final message = data is Map ? data['error']?.toString() : null;
      throw StateError(message ?? 'Cloudinary signing endpoint returned status ' + signatureResponse.status.toString());
    }
    final signed = Map<String, dynamic>.from(signatureResponse.data as Map);
    final uri = Uri.https(
      'api.cloudinary.com',
      '/v1_1/' + signed['cloud_name'].toString() + '/image/upload',
    );
    final upload = http.MultipartRequest('POST', uri);
    upload.fields['api_key'] = signed['api_key'].toString();
    upload.fields['timestamp'] = signed['timestamp'].toString();
    upload.fields['folder'] = signed['folder'].toString();
    upload.fields['signature'] = signed['signature'].toString();
    upload.files.add(await http.MultipartFile.fromPath('file', file.path));
    final response = await upload.send().timeout(const Duration(seconds: 60));
    final responseBody = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Cloudinary returned status ' + response.statusCode.toString() + ': ' + responseBody);
    }
    final payload = jsonDecode(responseBody);
    if (payload is! Map || payload['secure_url'] is! String) {
      throw StateError('Cloudinary did not return a secure image URL.');
    }
    return payload['secure_url'] as String;
  }

  Widget _bannerManagement() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Homepage banners', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        SizedBox(height: 4), Text('Publish or update the customer carousel anytime.', style: TextStyle(fontSize: 12, color: Color(0xFF68736D))),
      ])),
      FilledButton.icon(onPressed: () => _editBanner(), icon: const Icon(Icons.add_rounded), label: const Text('Add')),
    ]),
    const SizedBox(height: 10),
    StreamBuilder<List<Map<String, dynamic>>>(
      stream: client.from('app_banners').stream(primaryKey: ['id']).order('priority'),
      builder: (context, s) {
        if (s.hasError) return _error('Banners unavailable. Check admin role and app_banners permissions.');
        if (!s.hasData) return const LinearProgressIndicator();
        if (s.data!.isEmpty) return _empty('No banners yet', 'Add a banner with a headline and HTTPS image URL, then publish it.');
        return Column(children: s.data!.map((b) => Card(elevation: 0, margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 48, height: 48, child: (b['image_url']?.toString().isNotEmpty ?? false) ? Image.network(b['image_url'].toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined)) : const Icon(Icons.image_outlined))),
          title: Text(b['title']?.toString() ?? 'Banner', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${b['active'] == true ? 'Published' : 'Draft'} · Priority ${b['priority'] ?? 100}'),
          trailing: Wrap(spacing: 0, children: [
            IconButton(tooltip: 'Edit', onPressed: () => _editBanner(b), icon: const Icon(Icons.edit_outlined)),
            IconButton(tooltip: 'Delete', onPressed: () => _deleteBanner(b), icon: const Icon(Icons.delete_outline_rounded)),
            Switch(value: b['active'] == true, onChanged: (v) => _setBannerActive(b, v)),
          ]),
        ))).toList());
      },
    ),
    const SizedBox(height: 20),
  ]);

  Future<void> _editBanner([Map<String, dynamic>? existing]) async {
    final title = TextEditingController(text: existing?['title']?.toString() ?? '');
    final subtitle = TextEditingController(text: existing?['subtitle']?.toString() ?? '');
    final image = TextEditingController(text: existing?['image_url']?.toString() ?? '');
    final actionValue = TextEditingController(text: existing?['action_value']?.toString() ?? '');
    final priority = TextEditingController(text: (existing?['priority'] ?? 100).toString());
    var action = existing?['action_type']?.toString() ?? 'none';
    var active = existing?['active'] == true;
    var uploading = false;
    try {
      final save = await showDialog<bool>(context: context, builder: (dc) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(existing == null ? 'New banner' : 'Edit banner'),
        content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 120, decoration: const InputDecoration(labelText: 'Headline *', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: subtitle, maxLength: 240, maxLines: 2, decoration: const InputDecoration(labelText: 'Subtitle', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: image, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Image URL (HTTPS)', border: OutlineInputBorder())),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
            onPressed: uploading ? null : () async {
              try {
                final selectedFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 86, maxWidth: 1800);
                if (selectedFile == null) return;
                setDialogState(() => uploading = true);
                final uploadedUrl = await _uploadBannerImage(selectedFile);
                setDialogState(() => image.text = uploadedUrl);
                notice('Banner image uploaded to Cloudinary.');
              } catch (e) {
                notice('Image upload failed: ' + e.toString());
              } finally {
                setDialogState(() => uploading = false);
              }
            },
            icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_outlined),
            label: Text(uploading ? 'Uploading image…' : 'Choose image and upload to Cloudinary'),
          )),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: action, decoration: const InputDecoration(labelText: 'Tap action', border: OutlineInputBorder()), items: const [
            DropdownMenuItem(value: 'none', child: Text('No action')),
            DropdownMenuItem(value: 'service', child: Text('Open service')),
            DropdownMenuItem(value: 'offer', child: Text('Show offer message')),
            DropdownMenuItem(value: 'url', child: Text('External URL')),
          ], onChanged: (v) { if (v != null) setDialogState(() => action = v); }),
          const SizedBox(height: 10),
          TextField(controller: actionValue, maxLength: 500, decoration: InputDecoration(labelText: action == 'service' ? 'Service name (Food, Shop, Rides, Parcel)' : 'Action value', border: const OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: priority, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Display priority (lower first)', border: OutlineInputBorder())),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Published'), value: active, onChanged: (v) => setDialogState(() => active = v)),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')), FilledButton(onPressed: uploading ? null : () => Navigator.pop(dc, true), child: const Text('Save'))],
      )));
      if (save != true) return;
      if (title.text.trim().length < 2) { notice('Headline must contain at least 2 characters.'); return; }
      final payload = <String, dynamic>{
        'title': title.text.trim(), 'subtitle': subtitle.text.trim(),
        'image_url': image.text.trim().isEmpty ? null : image.text.trim(),
        'action_type': action, 'action_value': actionValue.text.trim().isEmpty ? null : actionValue.text.trim(),
        'area_code': existing?['area_code']?.toString() ?? 'DEFAULT',
        'priority': int.tryParse(priority.text.trim()) ?? 100, 'active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (existing == null) {
        payload['created_by'] = user?.id;
        await client.from('app_banners').insert(payload);
      } else {
        await client.from('app_banners').update(payload).eq('id', existing['id']);
      }
      notice('Banner saved and published to Supabase.');
    } catch (e) { notice('Could not save banner: ' + e.toString()); }
    finally { title.dispose(); subtitle.dispose(); image.dispose(); actionValue.dispose(); priority.dispose(); }
  }

  Future<void> _setBannerActive(Map<String, dynamic> banner, bool active) async {
    try {
      await client.from('app_banners').update({'active': active, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', banner['id']);
      notice(active ? 'Banner published.' : 'Banner unpublished.');
    } catch (e) { notice('Could not update banner: ' + e.toString()); }
  }

  Future<void> _deleteBanner(Map<String, dynamic> banner) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete banner?'), content: Text('“${banner['title'] ?? 'Banner'}” will be removed.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (yes != true) return;
    try { await client.from('app_banners').delete().eq('id', banner['id']); notice('Banner deleted.'); }
    catch (e) { notice('Could not delete banner: ' + e.toString()); }
  }

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
      const Text('Product approvals', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('seller_products').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Product catalogue unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No products submitted', 'Seller product drafts will appear here for review.');
          return Column(children: s.data!.take(20).map((product) => Card(elevation: 0, child: ListTile(
            title: Text(product['name']?.toString() ?? 'Product'),
            subtitle: Text('Status: ' + (product['status']?.toString() ?? 'draft') + ' · ₹' + (((product['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Activate product', onPressed: () => setProductStatus(product, 'active'), icon: const Icon(Icons.check_circle_outline, color: Colors.green)),
              IconButton(tooltip: 'Pause product', onPressed: () => setProductStatus(product, 'paused'), icon: const Icon(Icons.pause_circle_outline)),
              IconButton(tooltip: 'Reject product', onPressed: () => setProductStatus(product, 'rejected'), icon: const Icon(Icons.block_outlined)),
            ]),
          ))).toList());
        },
      ),

      const SizedBox(height: 22),
      const Text('Dark stores', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.icon(onPressed: createDarkStore, icon: const Icon(Icons.add_business_rounded), label: const Text('Create dark store')))),
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


  Widget _adminOrdersPage() => Scaffold(
    appBar: _appBar('Orders & dispatch'),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Customer orders', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('orders').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Orders unavailable. Check the admin RLS policy.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No orders yet', 'Orders appear when a customer checks out.');
          return Column(children: s.data!.take(30).map((o) => Card(elevation: 0, child: ListTile(
            title: Text('Order ' + _short(o['id']), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Status: ' + (o['status']?.toString() ?? 'unknown') + ' · Payment: ' + (o['payment_status']?.toString() ?? 'unknown') + ' · Total ₹' + (((o['total_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
            trailing: IconButton(
              tooltip: 'Assign to dark store',
              onPressed: (o['payment_status']?.toString() ?? 'pending') == 'paid' ? () => assignOrderToDarkStore(o) : null,
              icon: const Icon(Icons.warehouse_outlined),
            ),
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
          return Column(children: s.data!.take(25).map((r) => Card(elevation: 0, child: ListTile(
            title: Text((r['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (r['destination_label']?.toString() ?? 'Destination')),
            subtitle: Text('Status: ' + (r['status']?.toString() ?? 'unknown') + ' · Type: ' + (r['vehicle_type']?.toString() ?? 'bike')),
            trailing: IconButton(tooltip: 'Assign driver', icon: const Icon(Icons.person_add_alt_1_rounded), onPressed: () => assignRide(r)),
          ))).toList());
        },
      ),
      const SizedBox(height: 22),
      const Text('Delivery assignments', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('delivery_jobs').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Delivery jobs unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No delivery jobs', 'Jobs appear when an order or parcel needs delivery.');
          return Column(children: s.data!.take(25).map((j) => Card(elevation: 0, child: ListTile(
            title: Text((j['job_type']?.toString() ?? 'order').toUpperCase() + ' · ' + _short(j['id'])),
            subtitle: Text('Status: ' + (j['status']?.toString() ?? 'unknown')),
            trailing: IconButton(tooltip: 'Assign delivery partner', icon: const Icon(Icons.local_shipping_rounded), onPressed: () => assignDelivery(j)),
          ))).toList());
        },
      ),
    ]),
  );

  Widget _adminPartnersPage() => Scaffold(
    appBar: _appBar('Partners & approvals'),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Grant an app role', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
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
      const Text('Seller approvals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('sellers').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Seller records unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No seller applications', 'Seller applications will appear here.');
          return Column(children: s.data!.map((seller) => Card(elevation: 0, child: ListTile(
            title: Text(seller['display_name']?.toString() ?? 'Seller'),
            subtitle: Text('Status: ' + (seller['status']?.toString() ?? 'pending')),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Approve seller', onPressed: () => setSellerStatus(seller, 'approved'), icon: const Icon(Icons.check_circle_outline, color: Colors.green)),
              IconButton(tooltip: 'Suspend seller', onPressed: () => setSellerStatus(seller, 'suspended'), icon: const Icon(Icons.block_outlined)),
            ]),
          ))).toList());
        },
      ),
      const SizedBox(height: 24),
      const Text('Catalogue approvals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('seller_products').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Product catalogue unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No products submitted', 'Seller drafts appear here for review.');
          return Column(children: s.data!.take(30).map((product) => Card(elevation: 0, child: ListTile(
            title: Text(product['name']?.toString() ?? 'Product'),
            subtitle: Text('Status: ' + (product['status']?.toString() ?? 'draft') + ' · ₹' + (((product['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Activate product', onPressed: () => setProductStatus(product, 'active'), icon: const Icon(Icons.check_circle_outline, color: Colors.green)),
              IconButton(tooltip: 'Pause product', onPressed: () => setProductStatus(product, 'paused'), icon: const Icon(Icons.pause_circle_outline)),
              IconButton(tooltip: 'Reject product', onPressed: () => setProductStatus(product, 'rejected'), icon: const Icon(Icons.block_outlined)),
            ]),
          ))).toList());
        },
      ),
      const SizedBox(height: 24),
      Row(children: [
        const Expanded(child: Text('Dark stores', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        FilledButton.icon(onPressed: createDarkStore, icon: const Icon(Icons.add_business_rounded), label: const Text('Create')),
      ]),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('dark_stores').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Dark stores unavailable.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No dark stores', 'Create and approve dark stores from these tools.');
          return Column(children: s.data!.map((store) => Card(elevation: 0, child: ListTile(
            title: Text(store['name']?.toString() ?? 'Dark store'),
            subtitle: Text('Status: ' + (store['status']?.toString() ?? 'pending')),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Activate', onPressed: () => setStoreStatus(store, 'active'), icon: const Icon(Icons.check_circle_outline, color: Colors.green)),
              IconButton(tooltip: 'Suspend', onPressed: () => setStoreStatus(store, 'suspended'), icon: const Icon(Icons.block_outlined)),
            ]),
          ))).toList());
        },
      ),
      const SizedBox(height: 24),
      const AdminServiceConfigPanel(),
    ]),
  );

  Widget _sellerProductsPage() => Scaffold(
    appBar: _appBar('Products & inventory'),
    body: FutureBuilder<Map<String, dynamic>?>(future: sellerProfile, builder: (context, profile) {
      if (profile.hasError) return _error('Seller profile unavailable.');
      if (!profile.hasData) return const Center(child: CircularProgressIndicator());
      final seller = profile.data;
      if (seller == null) return _empty('Seller profile not linked', 'Ask Alteo Admin to link your seller account.');
      final sellerId = seller['id'] as String;
      if (seller['status'] != 'approved') return _empty('Approval pending', 'Product creation unlocks after Admin approves the seller profile.');
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const Expanded(child: Text('Your catalogue', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
          FilledButton.icon(onPressed: () => _editSellerProduct(sellerId), icon: const Icon(Icons.add_rounded), label: const Text('Add product')),
        ]),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: client.from('seller_products').stream(primaryKey: ['id']).eq('seller_id', sellerId).order('created_at', ascending: false),
          builder: (context, s) {
            if (s.hasError) return _error('Catalogue unavailable. Check seller permissions.');
            if (!s.hasData) return const LinearProgressIndicator();
            if (s.data!.isEmpty) return _empty('No products yet', 'Add products as drafts; Admin must approve them before they appear to customers.');
            return Column(children: s.data!.map((p) => Card(elevation: 0, child: ListTile(
              leading: (p['image_url']?.toString().startsWith('https://') ?? false)
                ? ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.network(p['image_url'].toString(), width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2_outlined)))
                : const Icon(Icons.inventory_2_outlined),
              title: Text(p['name']?.toString() ?? 'Product', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Status: ' + (p['status']?.toString() ?? 'draft') + ' · ₹' + (((p['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
              trailing: IconButton(tooltip: 'Edit product', onPressed: () => _editSellerProduct(sellerId, p), icon: const Icon(Icons.edit_outlined)),
            ))).toList());
          },
        ),
        const SizedBox(height: 24),
        const Text('Inventory update', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const Text('Use the stock edit action on each product, or update stock from this section.', style: TextStyle(color: Color(0xFF68736D))),
      ]);
    }),
  );

  Future<void> _editSellerProduct(String sellerId, [Map<String, dynamic>? existing]) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final description = TextEditingController(text: existing?['description']?.toString() ?? '');
    final price = TextEditingController(text: existing == null ? '' : (((existing['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2));
    final image = TextEditingController(text: existing?['image_url']?.toString() ?? '');
    var kind = existing?['kind']?.toString() ?? 'shopping';
    try {
      final saved = await showDialog<bool>(context: context, builder: (dc) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(existing == null ? 'New product draft' : 'Edit product'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, maxLength: 140, decoration: const InputDecoration(labelText: 'Product name *', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: kind, decoration: const InputDecoration(labelText: 'Category'), items: const [
            DropdownMenuItem(value: 'shopping', child: Text('Shopping')),
            DropdownMenuItem(value: 'quick', child: Text('Quick commerce')),
            DropdownMenuItem(value: 'food', child: Text('Food')),
          ], onChanged: (v) { if (v != null) setDialogState(() => kind = v); }),
          const SizedBox(height: 10),
          TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price in rupees *', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: image, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Image HTTPS URL (Cloudinary)', border: OutlineInputBorder())),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Save draft')),
        ],
      )));
      if (saved != true) return;
      final parsedPrice = double.tryParse(price.text.trim());
      final productName = name.text.trim();
      if (productName.length < 2 || parsedPrice == null || parsedPrice <= 0) {
        notice('Enter a product name and a valid price greater than zero.');
        return;
      }
      final payload = <String, dynamic>{
        'name': productName,
        'kind': kind,
        'description': description.text.trim().isEmpty ? null : description.text.trim(),
        'price_minor': (parsedPrice * 100).round(),
        'image_url': image.text.trim().isEmpty ? null : image.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (existing == null) {
        payload['seller_id'] = sellerId;
        payload['status'] = 'draft';
        payload['currency'] = 'INR';
        await client.from('seller_products').insert(payload);
      } else {
        await client.from('seller_products').update(payload).eq('id', existing['id']).eq('seller_id', sellerId);
      }
      notice(existing == null ? 'Product saved as a draft for Admin review.' : 'Product updated.');
    } catch (e) {
      notice('Could not save product: ' + e.toString());
    } finally {
      name.dispose(); description.dispose(); price.dispose(); image.dispose();
    }
  }

  Widget _sellerOrdersPage() => Scaffold(
    appBar: _appBar('Orders to fulfil'),
    body: FutureBuilder<Map<String, dynamic>?>(future: sellerProfile, builder: (context, profile) {
      if (profile.hasError) return _error('Seller profile unavailable.');
      if (!profile.hasData) return const Center(child: CircularProgressIndicator());
      final seller = profile.data;
      if (seller == null || seller['status'] != 'approved') return _empty('Seller approval pending', 'Order processing unlocks after Admin approves the seller profile.');
      final sellerId = seller['id'] as String;
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('orders').stream(primaryKey: ['id']).eq('seller_id', sellerId).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Seller orders unavailable.');
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return _empty('No orders yet', 'Orders routed to this seller appear here after checkout is enabled.');
          return ListView(padding: const EdgeInsets.all(16), children: s.data!.map((o) {
            final status = o['status']?.toString() ?? 'pending_payment';
            final payment = o['payment_status']?.toString() ?? 'pending';
            final buttons = <Widget>[];
            if (payment == 'paid' && status == 'paid') buttons.add(FilledButton(onPressed: () => rpc('seller_update_order_status', {'p_order_id': o['id'], 'p_action': 'accept'}, 'Order accepted.'), child: const Text('Accept')));
            if (payment == 'paid' && status == 'accepted') buttons.add(FilledButton(onPressed: () => rpc('seller_update_order_status', {'p_order_id': o['id'], 'p_action': 'prepare'}, 'Order preparation started.'), child: const Text('Prepare')));
            if (payment == 'paid' && status == 'preparing') buttons.add(FilledButton(onPressed: () => rpc('seller_update_order_status', {'p_order_id': o['id'], 'p_action': 'ready'}, 'Order ready for pickup.'), child: const Text('Ready for pickup')));
            return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Order ' + _short(o['id']), style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text('Status: ' + status + ' · Payment: ' + payment + ' · Total ₹' + (((o['total_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
              if (buttons.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, children: buttons)),
            ])));
          }).toList());
        },
      );
    }),
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
      if (seller == null) return _empty('Seller profile not linked', 'Ask Alteo admin to create or approve your seller profile.');
      final sellerId = seller['id'] as String;
      if (seller['status'] != 'approved') return _empty('Seller approval pending', 'Your seller profile status is ' + (seller['status']?.toString() ?? 'pending') + '. Catalogue and order processing unlock after approval.');
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Your catalogue', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: client.from('seller_products').stream(primaryKey: ['id']).eq('seller_id', sellerId).order('created_at', ascending: false),
          builder: (context, s) {
            if (s.hasError) return _error('Catalogue unavailable. Check seller RLS policies.');
            if (!s.hasData) return const LinearProgressIndicator();
            if (s.data!.isEmpty) return _empty('No products yet', 'Product creation is available after catalogue permissions are configured.');
            return Column(children: s.data!.map((p) => Card(elevation: 0, child: ListTile(
              title: Text(p['name']?.toString() ?? 'Product'),
              subtitle: Text('Status: ' + (p['status']?.toString() ?? 'draft') + ' · ₹' + (((p['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
              trailing: IconButton(tooltip: 'Update stock', icon: const Icon(Icons.inventory_2_outlined), onPressed: () => _setSellerStock(sellerId, p)),
            ))).toList());
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


  Widget _darkStorePickingPage() => Scaffold(
    appBar: _appBar('Picking & packing'),
    body: FutureBuilder<Map<String, dynamic>?>(future: storeProfile, builder: (context, profile) {
      if (profile.hasError) return _error('Dark-store profile unavailable.');
      if (!profile.hasData) return const Center(child: CircularProgressIndicator());
      final store = profile.data;
      if (store == null) return _empty('Dark store not linked', 'Ask Admin to create and assign a dark store to your account.');
      if (store['status'] != 'active') return _empty('Store not active', 'Admin activation is required before picking tasks are available.');
      final storeId = store['id'] as String;
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('dark_store_tasks').stream(primaryKey: ['id']).eq('store_id', storeId).order('created_at', ascending: false),
        builder: (context, tasks) {
          if (tasks.hasError) return _error('Picking queue unavailable. Check dark-store task permissions.');
          if (!tasks.hasData) return const Center(child: CircularProgressIndicator());
          if (tasks.data!.isEmpty) return _empty('No picking tasks', 'Admin can assign a paid customer order to this active store from Admin → Orders.');
          return ListView(padding: const EdgeInsets.all(16), children: tasks.data!.map((task) {
            final status = task['status']?.toString() ?? 'assigned';
            String? action;
            String actionLabel = '';
            if (status == 'assigned') { action = 'accept'; actionLabel = 'Accept task'; }
            if (status == 'accepted') { action = 'start_picking'; actionLabel = 'Start picking'; }
            if (status == 'picking') { action = 'packed'; actionLabel = 'Mark packed'; }
            if (status == 'packed') { action = 'handed_over'; actionLabel = 'Hand over to delivery'; }
            final orderId = task['order_id']?.toString() ?? '';
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5EAE5))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.inventory_2_rounded, color: Color(0xFF176B57)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Order ' + _short(orderId), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: const Color(0xFFE3F2E9), borderRadius: BorderRadius.circular(9)),
                      child: Text(status.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF176B57))),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  FutureBuilder<Map<String, dynamic>?>(
                    future: client.from('orders').select('id,status,payment_status,total_minor,order_items(product_name_snapshot,quantity,unit_price_minor)')
                      .eq('id', orderId).maybeSingle(),
                    builder: (context, orderSnapshot) {
                      if (orderSnapshot.hasError) return const Text('Order detail is restricted or temporarily unavailable.');
                      if (!orderSnapshot.hasData) return const LinearProgressIndicator();
                      final order = orderSnapshot.data;
                      if (order == null) return const Text('Order details are no longer available.');
                      final items = (order['order_items'] as List? ?? const []).map((row) => Map<String, dynamic>.from(row as Map)).toList();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Order state: ' + (order['status']?.toString() ?? 'unknown') + ' · Payment: ' + (order['payment_status']?.toString() ?? 'unknown')),
                        const SizedBox(height: 6),
                        for (final item in items.take(12))
                          Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• ' + (item['product_name_snapshot']?.toString() ?? 'Item') + ' × ' + (item['quantity']?.toString() ?? '1'))),
                      ]);
                    },
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => rpc('dark_store_update_task', {'p_task_id': task['id'], 'p_action': action}, actionLabel + ' completed.'),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(actionLabel),
                      ),
                    ),
                  ] else if (status == 'handed_over')
                    const Padding(padding: EdgeInsets.only(top: 10), child: Row(children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green),
                      SizedBox(width: 7),
                      Text('Handed over to dispatch', style: TextStyle(fontWeight: FontWeight.w800)),
                    ])),
                ]),
              ),
            );
          }).toList());
        },
      );
    }),
  );

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


class AdminServiceConfigPanel extends StatefulWidget {
  const AdminServiceConfigPanel({super.key});
  @override
  State<AdminServiceConfigPanel> createState() => _AdminServiceConfigPanelState();
}

class _AdminServiceConfigPanelState extends State<AdminServiceConfigPanel> {
  SupabaseClient get client => Supabase.instance.client;
  static const services = <String, String>{
    'ride': 'Rides',
    'parcel': 'Parcels',
    'food': 'Food',
    'quick': 'Quick commerce',
    'shopping': 'Shopping',
  };

  void message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> setControl(String service, bool enabled, bool automatic) async {
    try {
      if (enabled) {
        final price = await client.from('pricing_rules').select('id').eq('service', service).eq('city_code', 'DEFAULT').eq('active', true).maybeSingle();
        if (price == null) {
          message('Configure active DEFAULT pricing for ' + services[service]! + ' before enabling it.');
          return;
        }
      }
      await client.rpc('admin_set_service_control', params: {
        'p_area_code': 'DEFAULT',
        'p_service': service,
        'p_enabled': enabled,
        'p_automatic_assignment': automatic,
      });
      message(services[service]! + ' settings updated.');
    } catch (e) {
      message('Could not update service settings: ' + e.toString());
    }
  }

  Future<void> editPricing(String service, Map<String, dynamic>? existing) async {
    final base = TextEditingController(text: (((existing?['base_fee_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0));
    final perKm = TextEditingController(text: (((existing?['per_km_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0));
    final minimum = TextEditingController(text: (((existing?['minimum_fee_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0));
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text('DEFAULT pricing · ' + services[service]!),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: base, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base fee (₹)')),
          TextField(controller: perKm, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Per kilometre (₹)')),
          TextField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum fee (₹)')),
          const SizedBox(height: 8),
          const Text('Choose your real prices carefully. These values are used by server-side booking and checkout calculations.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save pricing')),
        ],
      ));
      if (ok != true) return;
      final b = int.tryParse(base.text.trim());
      final k = int.tryParse(perKm.text.trim());
      final m = int.tryParse(minimum.text.trim());
      if (b == null || k == null || m == null || b < 0 || k < 0 || m < 0) {
        message('Enter non-negative whole-rupee amounts.');
        return;
      }
      await client.from('pricing_rules').upsert({
        'service': service,
        'city_code': 'DEFAULT',
        'base_fee_minor': b * 100,
        'per_km_minor': k * 100,
        'minimum_fee_minor': m * 100,
        'active': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'service,city_code');
      message('Pricing saved for ' + services[service]! + '.');
    } catch (e) {
      message('Could not save pricing: ' + e.toString());
    } finally {
      base.dispose();
      perKm.dispose();
      minimum.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Service controls and pricing', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
    const SizedBox(height: 5),
    const Text('Enable services only after setting real DEFAULT pricing. Automatic dispatch remains off until you switch it on.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
    const SizedBox(height: 10),
    StreamBuilder<List<Map<String, dynamic>>>(
      stream: client.from('service_controls').stream(primaryKey: ['id']).eq('area_code', 'DEFAULT'),
      builder: (context, controlsSnapshot) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('pricing_rules').stream(primaryKey: ['id']).eq('city_code', 'DEFAULT'),
        builder: (context, pricingSnapshot) {
          if (controlsSnapshot.hasError || pricingSnapshot.hasError) return const Text('Service settings unavailable. Check admin policies.');
          if (!controlsSnapshot.hasData || !pricingSnapshot.hasData) return const LinearProgressIndicator();
          final controls = <String, Map<String, dynamic>>{
            for (final row in controlsSnapshot.data!) (row['service'] as String): row,
          };
          final prices = <String, Map<String, dynamic>>{
            for (final row in pricingSnapshot.data!) row['service'] as String: row,
          };
          return Column(children: services.entries.map((entry) {
            final service = entry.key;
            final control = controls[service];
            final price = prices[service];
            final enabled = control?['enabled'] as bool? ?? false;
            final automatic = control?['automatic_assignment'] as bool? ?? false;
            final activePrice = price?['active'] as bool? ?? false;
            final priceLabel = price == null
              ? 'Pricing not configured'
              : 'Base ₹' + (((price['base_fee_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)
                + ' · /km ₹' + (((price['per_km_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)
                + ' · Minimum ₹' + (((price['minimum_fee_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)
                + (activePrice ? '' : ' · inactive');
            return Card(elevation: 0, color: Colors.white, margin: const EdgeInsets.only(bottom: 10), child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(enabled ? 'Enabled in DEFAULT area' : 'Disabled in DEFAULT area'),
                  value: enabled,
                  onChanged: (value) => setControl(service, value, automatic),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatic assignment'),
                  subtitle: const Text('Off means admin-controlled assignment'),
                  value: automatic,
                  onChanged: (value) => setControl(service, enabled, value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pricing'),
                  subtitle: Text(priceLabel),
                  trailing: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Configure pricing', onPressed: () => editPricing(service, price)),
                ),
              ]),
            ));
          }).toList());
        },
      ),
    ),
  ]);
}

class _Feature {
  const _Feature(this.title, this.subtitle, this.detail, this.icon);
  final String title, subtitle, detail;
  final IconData icon;
}

const _features = <_Feature>[
  _Feature('Order operations', 'Review order stages and exceptions', 'Authorised staff can review incoming orders, resolve exceptions and track fulfilment from one place.', Icons.receipt_long_rounded),
  _Feature('Partner assignments', 'Drivers and delivery partners', 'Assign eligible work to authorised partners and follow status changes across the platform.', Icons.assignment_ind_rounded),
  _Feature('Seller approvals', 'Marketplace partner management', 'Review seller onboarding, catalogue readiness and operational eligibility.', Icons.storefront_rounded),
  _Feature('Service controls', 'Rides, food, quick commerce and parcels', 'Manage service availability and operational settings with server-side permissions.', Icons.tune_rounded),
  _Feature('Reports and reconciliation', 'Operational visibility', 'Review order volumes, fulfilment performance and financial summaries when reporting is connected.', Icons.analytics_rounded),
];

class RolePublicFeaturePage extends StatelessWidget {
  const RolePublicFeaturePage({super.key, required this.feature, required this.onSignIn, this.selectedIndex = 0, this.onNavigate});
  final _Feature feature;
  final VoidCallback onSignIn;
  final int selectedIndex;
  final ValueChanged<int>? onNavigate;

  List<String> get _navLabels => switch (requiredRole) {
    'admin' => const ['Home', 'Orders', 'Banners', 'Partners', 'Profile'],
    'driver_partner' => const ['Home', 'Rides', 'Earnings', 'Profile'],
    'delivery_partner' => const ['Home', 'Deliveries', 'Earnings', 'Profile'],
    'seller' => const ['Home', 'Orders', 'Products', 'Profile'],
    'dark_store' => const ['Home', 'Picking', 'Inventory', 'Profile'],
    _ => const ['Home', 'Activity', 'Services', 'Profile'],
  };

  IconData _navIcon(String label, bool selected) => switch (label) {
    'Home' => selected ? Icons.home_rounded : Icons.home_outlined,
    'Orders' => selected ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
    'Banners' => selected ? Icons.view_carousel_rounded : Icons.view_carousel_outlined,
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
