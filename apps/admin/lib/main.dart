import 'dart:async';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alteo_notifications/alteo_notifications.dart';
import 'package:alteo_partner_ui/alteo_partner_ui.dart';

const appName = 'Alteo Admin';
const requiredRole = 'admin';
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
Future<void>? _googleSignInInitialization;
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://nkerkoptbrcadlpxffkn.supabase.co');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_lM6ttzw8KMPH2BNXgMAJVA_3y1h51YD');
final ValueNotifier<ThemeMode> roleThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
final ValueNotifier<String> roleLanguage = ValueNotifier<String>('English');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAlteoPartnerPreferences(appId: requiredRole, themeMode: roleThemeMode, language: roleLanguage);
  var backendReady = false;
  try {
    if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
      backendReady = true;
    }
  } catch (_) {
    // Public exploration must work even when auth or backend configuration is unavailable.
  }
  if (backendReady) {
    unawaited(AlteoPushNotifications.instance.initialize(
      client: Supabase.instance.client,
      appId: 'admin',
    ));
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
          message = 'Google sign-in succeeded. This account is signed in, but it has not been granted the $requiredRole role yet. Protected operations stay locked until an administrator approves the role.';
        });
        if (authSheetOpen && mounted) Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Could not verify your app role. Check the user_roles policy and try again.');
    }
  }

  Future<void> signInWithGoogle() async {
    if (!widget.backendReady) {
      setState(() => message = 'Sign-in is temporarily unavailable. Please try again later.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      if (googleWebClientId.isEmpty) {
        throw const AuthException('Google native sign-in is not configured yet. Please set GOOGLE_WEB_CLIENT_ID in the release build.');
      }
      _googleSignInInitialization ??= GoogleSignIn.instance.initialize(
        serverClientId: googleWebClientId,
      );
      await _googleSignInInitialization;
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuthentication = googleUser.authentication;
      final idToken = googleAuthentication.idToken;
      if (idToken == null) {
        throw const AuthException('Google did not return an ID token. Check the Android OAuth client and signing SHA-1.');
      }
      final authorization = await googleUser.authorizationClient
          .authorizationForScopes(const ['email']);
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization?.accessToken,
      );
      if (mounted) {
        setState(() => message = 'Google sign-in completed. Checking your Alteo account access…');
      }
    } catch (e) {
      if (!mounted) return;
      final lower = e.toString().toLowerCase();
      debugPrint('Google sign-in failed (${e.runtimeType}).');
      setState(() => message = lower.contains('canceled') || lower.contains('cancelled')
          ? 'Google sign-in was cancelled.'
          : 'Google sign-in could not be completed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (authorized) return RoleOperationsPage(onSignOut: () async { await AlteoPushNotifications.instance.unregisterCurrentDevice(); await Supabase.instance.client.auth.signOut(); if (mounted) setState(() => authorized = false); });
    return Scaffold(
    appBar: AppBar(
      title: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF155C4B), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 10),
        const Expanded(child: Text(appName, style: TextStyle(fontWeight: FontWeight.w800))),
      ]),
      actions: [TextButton(onPressed: () => showAuth(context), child: Text(authorized ? 'Access' : (widget.backendReady && Supabase.instance.client.auth.currentSession != null ? 'Account' : 'Sign in')))],
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
        if (message != null && !authorized)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8D49A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF8A6414)),
                const SizedBox(width: 10),
                Expanded(child: Text(message!, style: const TextStyle(height: 1.45))),
                if (widget.backendReady && Supabase.instance.client.auth.currentSession != null)
                  IconButton(
                    tooltip: 'Log out',
                    onPressed: () => confirmAlteoLogout(context, onConfirm: () async {
                      await AlteoPushNotifications.instance.unregisterCurrentDevice(); await Supabase.instance.client.auth.signOut();
                      if (mounted) setState(() { authorized = false; message = null; });
                    }),
                    icon: const Icon(Icons.logout_rounded),
                  ),
              ],
            ),
          ),
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
              ? 'Some live features may be temporarily unavailable. Please try again later.'
              : 'Sign-in and live updates are temporarily unavailable. Please try again later.',
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
    'Modules' => selected ? Icons.grid_view_rounded : Icons.grid_view_outlined,
    'Catalogue' => selected ? Icons.inventory_2_rounded : Icons.inventory_2_outlined,
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
        const Text('Create, edit, reorder, publish or unpublish the swipeable carousel shown at the top of the Customer app. Banner changes appear automatically in the Customer app and do not require an app reinstall.', style: TextStyle(color: Color(0xFF68736D), height: 1.5)),
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
                    const Text('Live records appear when your account is authorised and new work becomes available.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
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
  Future<String>? _adminCatalogSellerFuture;
  final roleUserId = TextEditingController();
  String grantRole = 'delivery_partner';
  bool partnerOnline = false;
  int selectedTab = 0;
  final _notificationTitleController = TextEditingController();
  final _notificationBodyController = TextEditingController();
  final _notificationUserIdController = TextEditingController();
  String _notificationAudience = 'all_customers';
  bool _sendingNotification = false;
  String? _notificationResult;

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
    _notificationTitleController.dispose();
    _notificationBodyController.dispose();
    _notificationUserIdController.dispose();
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
      debugPrint('Admin/partner RPC action failed (${e.runtimeType}).');
      notice('We could not complete this action. Check your access and connection, then try again.');
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
      debugPrint('Availability update failed (${e.runtimeType}).');
      notice('Availability could not be updated. Check your connection and try again.');
    }
  }

  PreferredSizeWidget _partnerAppBar(String title) => AppBar(title: Text(title), actions: [
    TextButton.icon(
      onPressed: _setAvailability,
      icon: Icon(partnerOnline ? Icons.toggle_on_rounded : Icons.toggle_off_rounded),
      label: Text(partnerOnline ? 'Online' : 'Go online'),
    ),
    IconButton(tooltip: 'Log out', onPressed: () => confirmAlteoLogout(context, onConfirm: widget.onSignOut), icon: const Icon(Icons.logout_rounded)),
  ]);

  Future<void> grantUserRole() async {
    final id = roleUserId.text.trim();
    if (id.isEmpty) { notice('Enter the user UUID first.'); return; }
    await rpc('admin_grant_user_role', {'p_user_id': id, 'p_role': grantRole}, 'Role granted.');
    roleUserId.clear();
  }

  Future<void> reviewRoleRequest(Map<String, dynamic> request, {required bool approve}) async {
    final requestId = request['id']?.toString();
    final userId = request['user_id']?.toString();
    final requestedRole = request['requested_role']?.toString();
    if (requestId == null || userId == null || requestedRole == null) {
      notice('This approval request is missing required details.');
      return;
    }
    String? rejectionReason;
    if (!approve) {
      final controller = TextEditingController();
      try {
        final confirmed = await showDialog<bool>(context: context, builder: (dc) => AlertDialog(
          title: const Text('Reject onboarding'),
          content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason for rejection', hintText: 'Tell the applicant what needs to be corrected', border: OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Reject application')),
          ],
        ));
        if (confirmed != true) return;
        rejectionReason = controller.text.trim().isEmpty ? 'Please review your details and contact Alteo support if you need help.' : controller.text.trim();
      } finally { controller.dispose(); }
    }
    try {
      if (approve) {
        await client.rpc('admin_grant_user_role', params: {'p_user_id': userId, 'p_role': requestedRole});
      }
      await client.from('role_requests').update({
        'status': approve ? 'approved' : 'rejected',
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'reviewed_by': user?.id,
        'rejection_reason': approve ? null : rejectionReason,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', requestId);
      notice(approve ? 'Role approved. This role is available only in its separate Alteo app.' : 'Onboarding rejected. The applicant can correct details and resubmit.');
    } catch (e) {
      notice('Could not review role request: $e');
    }
  }

  Future<void> showPartnerApplication(Map<String, dynamic> request) async {
    final rawData = request['application_data'];
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    String? photoUrl;
    final photoPath = request['profile_photo_path']?.toString();
    if (photoPath != null && photoPath.isNotEmpty) {
      try { photoUrl = await client.storage.from('partner-onboarding').createSignedUrl(photoPath, 300); } catch (_) {}
    }
    if (!mounted) return;
    final details = <String>[
      'Role: ${(request['requested_role'] ?? 'unknown').toString().replaceAll('_', ' ')}',
      'Name: ${request['display_name'] ?? 'Not provided'}',
      'Email: ${request['email'] ?? 'Not provided'}',
      'Mobile: ${request['phone'] ?? 'Not provided'}',
      ...data.entries.map((e) => '${e.key.replaceAll('_', ' ')}: ${e.value}'),
    ].join('\n');
    await showDialog<void>(context: context, builder: (dc) => AlertDialog(
      title: const Text('Partner onboarding details'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (photoUrl != null) Center(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(photoUrl, height: 150, width: 150, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 80)))),
          if (photoUrl != null) const SizedBox(height: 14),
          SelectableText(details, style: const TextStyle(height: 1.6)),
          if ((request['rejection_reason']?.toString().isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            Text('Previous rejection reason: ${request['rejection_reason']}', style: const TextStyle(color: Colors.red)),
          ],
        ],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Close'))],
    ));
  }

  Widget _roleRequestsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Role approval requests', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('role_requests').stream(primaryKey: ['id'])
          .eq('status', 'pending').order('requested_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Approval requests unavailable. Check role_requests permissions.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No pending requests', 'Seller, driver, delivery partner and dark-store access requests will appear here.');
          return Column(children: s.data!.map((request) {
            final role = request['requested_role']?.toString() ?? 'unknown';
            final name = request['display_name']?.toString().trim();
            final email = request['email']?.toString().trim();
            final identity = (name != null && name.isNotEmpty) ? name : ((email != null && email.isNotEmpty) ? email : _short(request['user_id']?.toString() ?? ''));
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => showPartnerApplication(request),
                leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
                title: Text(identity, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${role.replaceAll('_', ' ')} · ${request['phone'] ?? 'No mobile number'} · ${email ?? _short(request['user_id']?.toString() ?? '')}'),
                trailing: Wrap(spacing: 0, children: [
                  IconButton(tooltip: 'View application', onPressed: () => showPartnerApplication(request), icon: const Icon(Icons.visibility_outlined)),
                  IconButton(tooltip: 'Approve request', onPressed: () => reviewRoleRequest(request, approve: true), icon: const Icon(Icons.check_circle_outline, color: Colors.green)),
                  IconButton(tooltip: 'Reject request', onPressed: () => reviewRoleRequest(request, approve: false), icon: const Icon(Icons.cancel_outlined, color: Colors.red)),
                ]),
              ),
            );
          }).toList());
        },
      ),
      const SizedBox(height: 20),
    ],
  );

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
    if (status == 'active') {
      final imageUrl = product['image_url']?.toString() ?? '';
      final description = product['description']?.toString().trim() ?? '';
      if (!imageUrl.startsWith('https://') || description.length < 3) {
        notice('This item needs an image and description before it can be published. Open Edit to review the details.');
        return;
      }
    }
    await rpc('admin_set_product_status', {'p_product_id': product['id'], 'p_status': status}, 'Product status updated.');
  }

  Widget _productApprovalTile(Map<String, dynamic> product) {
    final imageUrl = product['image_url']?.toString() ?? '';
    final hasImage = imageUrl.startsWith('https://');
    final name = product['name']?.toString() ?? 'Product';
    final description = product['description']?.toString().trim() ?? '';
    final status = product['status']?.toString() ?? 'draft';
    final price = (((product['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2);
    final kind = (product['kind']?.toString() ?? 'shopping').toUpperCase();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 68,
            height: 76,
            child: hasImage
              ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, size: 30))
              : Container(color: const Color(0xFFFFF4E5), child: const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF9A5C13), size: 30)),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(description.isEmpty ? 'Description missing — review before publishing.' : description, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('₹$price · $kind · ${status.toUpperCase()}'),
              const SizedBox(height: 3),
              Text(hasImage ? 'Image attached' : 'Image required before publishing',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: hasImage ? const Color(0xFF176B57) : const Color(0xFFB3261E))),
            ],
          ),
        ),
        trailing: Wrap(
          spacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Activate product',
              onPressed: hasImage && description.length >= 3 ? () => setProductStatus(product, 'active') : null,
              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            ),
            IconButton(tooltip: 'Pause product', onPressed: () => setProductStatus(product, 'paused'), icon: const Icon(Icons.pause_circle_outline)),
            IconButton(tooltip: 'Reject product', onPressed: () => setProductStatus(product, 'rejected'), icon: const Icon(Icons.block_outlined)),
            IconButton(
              tooltip: 'Review full listing',
              onPressed: () => _editAdminProduct(product['seller_id']?.toString() ?? '', product),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
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
    'admin' => const ['Home', 'Orders', 'Modules', 'Profile'],
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
    'Notifications' => selected ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
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
    if (requiredRole == 'admin' && label == 'Modules') return _adminModulesPage();
    if (requiredRole == 'admin' && label == 'Catalogue') return _adminCataloguePage();
    if (requiredRole == 'admin' && label == 'Notifications') {
      return _adminNotificationsPage();
    }
    if (requiredRole == 'admin' && label == 'Banners') {
      return Scaffold(
        appBar: _appBar('Customer homepage banners'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            const Text('Customer homepage banners', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Manage the swipeable Customer home carousel here. Published changes appear automatically in the Customer app.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
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
        body: ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 28), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF2C8B70)]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Color(0x33FFFFFF), child: Icon(Icons.person_rounded, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.email ?? 'Alteo team member', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Role: $requiredRole', style: const TextStyle(color: Colors.white70)),
              ])),
            ]),
          ),
          if (requiredRole == 'seller')
            FutureBuilder<Map<String, dynamic>?>(
              future: sellerProfile,
              builder: (context, snapshot) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(top: 12),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.storefront_rounded, color: Color(0xFF176B57))),
                  title: Text(snapshot.data?['display_name']?.toString() ?? 'Seller business profile', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(snapshot.connectionState == ConnectionState.waiting
                    ? 'Loading business status…'
                    : snapshot.hasError
                      ? 'Business status could not be loaded. Retry from the Home screen.'
                      : 'Approval status: ${snapshot.data?['status']?.toString() ?? 'not available'}'),
                ),
              ),
            ),
          if (requiredRole == 'dark_store')
            FutureBuilder<Map<String, dynamic>?>(
              future: storeProfile,
              builder: (context, snapshot) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(top: 12),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.warehouse_rounded, color: Color(0xFF176B57))),
                  title: Text(snapshot.data?['name']?.toString() ?? 'Dark store profile', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(snapshot.connectionState == ConnectionState.waiting
                    ? 'Loading store status…'
                    : snapshot.hasError
                      ? 'Store status could not be loaded. Retry from the Home screen.'
                      : 'Approval status: ${snapshot.data?['status']?.toString() ?? 'not available'}'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const Icon(Icons.palette_outlined),
                const SizedBox(width: 12),
                const Expanded(child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.w800))),
                DropdownButton<ThemeMode>(
                  value: roleThemeMode.value,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                    DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    roleThemeMode.value = value;
                    unawaited(saveAlteoPartnerTheme(requiredRole, value));
                  },
                ),
              ]),
            ),
          ),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const Icon(Icons.language_rounded),
                const SizedBox(width: 12),
                const Expanded(child: Text('Language preference', style: TextStyle(fontWeight: FontWeight.w800))),
                ValueListenableBuilder<String>(
                  valueListenable: roleLanguage,
                  builder: (context, language, _) => DropdownButton<String>(
                    value: language,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'English', child: Text('English')),
                      DropdownMenuItem(value: 'हिन्दी', child: Text('हिन्दी')),
                      DropdownMenuItem(value: 'বাংলা', child: Text('বাংলা')),
                      DropdownMenuItem(value: 'தமிழ்', child: Text('தமிழ்')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      roleLanguage.value = value;
                      unawaited(saveAlteoPartnerLanguage(requiredRole, value));
                    },
                  ),
                ),
              ]),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text('Your language preference is saved. Some operational screens may remain in English until their translation is available.', style: TextStyle(fontSize: 12, color: Color(0xFF68736D), height: 1.4)),
          ),
          Card(elevation: 0, child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.tune_rounded, color: Color(0xFF176B57))),
            title: const Text('App permissions', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Manage location and notification access in Android settings'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlteoDevicePermissionsPage(appName: appName, includeLocation: false))),
          )),
          Card(elevation: 0, child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.support_agent_rounded, color: Color(0xFF176B57))),
            title: const Text('Help & support', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Send a request and check its status'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlteoHelpSupportPage(appName: appName, role: requiredRole))),
          )),
          Card(elevation: 0, child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.privacy_tip_outlined, color: Color(0xFF176B57))),
            title: const Text('Privacy information', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('How account, work and location data are used'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlteoPrivacyPage(appName: appName))),
          )),
          Card(elevation: 0, child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.description_outlined, color: Color(0xFF176B57))),
            title: const Text('Terms of use', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Operational rules for using this app'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlteoTermsPage(appName: appName, role: requiredRole))),
          )),
          Card(elevation: 0, child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.info_outline_rounded, color: Color(0xFF176B57))),
            title: const Text('About this app', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('App purpose and version information'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlteoAboutPage(appName: appName, role: requiredRole))),
          )),
          Card(elevation: 0, child: ListTile(
            leading: const Icon(Icons.security_rounded),
            title: const Text('Access & security', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Sign-in and role permissions protect operational records.'),
          )),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => confirmAlteoLogout(context, onConfirm: widget.onSignOut),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: const Color(0xFFB3261E), side: const BorderSide(color: Color(0xFFB3261E))),
          ),
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
    IconButton(tooltip: 'Log out', onPressed: () => confirmAlteoLogout(context, onConfirm: widget.onSignOut), icon: const Icon(Icons.logout_rounded)),
  ]);



  Future<String> _uploadAppMediaImage(XFile file, {required String folder}) async {
    if (folder != 'banners' && folder != 'items') {
      throw StateError('Unsupported media folder.');
    }
    final extension = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
    const allowedExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
    if (!allowedExtensions.contains(extension)) {
      throw StateError('Choose a JPG, PNG, WEBP, or GIF image.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('The selected image is empty.');
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Image must be 5 MB or smaller.');
    }
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    final safeExtension = extension == 'jpeg' ? 'jpg' : extension;
    final objectPath = folder + '/' + DateTime.now().toUtc().microsecondsSinceEpoch.toString() + '.' + safeExtension;
    try {
      await client.storage.from('app-media').uploadBinary(
        objectPath,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false),
      );
      return client.storage.from('app-media').getPublicUrl(objectPath);
    } on StorageException catch (e) {
      debugPrint('Admin media upload failed (${e.runtimeType}).');
      throw StateError('Image upload unavailable.');
    }
  }

  Future<String> _uploadBannerImage(XFile file) =>
      _uploadAppMediaImage(file, folder: 'banners');

  Future<String> _uploadCatalogImage(XFile file) =>
      _uploadAppMediaImage(file, folder: 'items');

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
                notice('Banner image uploaded successfully.');
              } catch (e) {
                debugPrint('Admin banner image upload failed (${e.runtimeType}).');
      notice('Image upload failed. Check the image type, file size and connection, then retry.');
              } finally {
                setDialogState(() => uploading = false);
              }
            },
            icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_outlined),
            label: Text(uploading ? 'Uploading image…' : 'Choose and upload image'),
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
      notice('Banner saved and published.');
    } catch (e) { debugPrint('Banner save failed (${e.runtimeType}).'); notice('Could not save the banner. Check the required fields and try again.'); }
    finally { title.dispose(); subtitle.dispose(); image.dispose(); actionValue.dispose(); priority.dispose(); }
  }

  Future<void> _setBannerActive(Map<String, dynamic> banner, bool active) async {
    try {
      await client.from('app_banners').update({'active': active, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', banner['id']);
      notice(active ? 'Banner published.' : 'Banner unpublished.');
    } catch (e) { debugPrint('Banner update failed (${e.runtimeType}).'); notice('Could not update the banner. Please retry.'); }
  }

  Future<void> _deleteBanner(Map<String, dynamic> banner) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete banner?'), content: Text('“${banner['title'] ?? 'Banner'}” will be removed.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (yes != true) return;
    try { await client.from('app_banners').delete().eq('id', banner['id']); notice('Banner deleted.'); }
    catch (e) { debugPrint('Banner deletion failed (${e.runtimeType}).'); notice('Could not delete the banner. Please retry.'); }
  }

  Future<void> _sendAdminPushNotification() async {
    final title = _notificationTitleController.text.trim();
    final body = _notificationBodyController.text.trim();
    final userId = _notificationUserIdController.text.trim();
    if (title.isEmpty || title.length > 100 || body.isEmpty || body.length > 1000) {
      notice('Enter a title (up to 100 characters) and message (up to 1,000 characters).');
      return;
    }
    if (_notificationAudience == 'specific_user' &&
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(userId)) {
      notice('Enter a valid customer user UUID.');
      return;
    }

    if (_notificationAudience == 'all_customers') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Send to all opted-in customers?'),
          content: Text('Title: $title\n\n$body\n\nThis sends a push notification to customer installs subscribed to Firebase notifications.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Send broadcast')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _sendingNotification = true;
      _notificationResult = null;
    });
    try {
      final payload = <String, dynamic>{
        'audience': _notificationAudience,
        'app_id': 'customer',
        'title': title,
        'body': body,
        'data': <String, String>{'screen': 'home', 'source': 'admin_broadcast'},
      };
      if (_notificationAudience == 'specific_user') payload['user_id'] = userId;
      final response = await client.functions.invoke('send-push-notification', body: payload);
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.status < 200 || response.status >= 300 || data['error'] != null) {
        throw StateError(data['error']?.toString() ?? ('Notification server returned HTTP ' + response.status.toString() + '.'));
      }

      final sent = (data['sent'] as num?)?.toInt() ?? 0;
      final attempted = (data['attempted'] as num?)?.toInt() ?? 0;
      String result;
      if (_notificationAudience == 'all_customers' && sent > 0) {
        result = 'Firebase accepted the broadcast for the alteo_customers topic. Delivery depends on notification permission, network and device settings.';
      } else if (sent > 0) {
        result = 'Firebase accepted $sent of $attempted registered customer device message(s).';
      } else {
        result = data['message']?.toString() ?? 'No registered customer devices were found. Open the Customer app, sign in and allow notifications first.';
      }
      if (mounted) setState(() => _notificationResult = result);
    } catch (error) {
      if (mounted) setState(() => _notificationResult = 'Could not send notification: $error');
    } finally {
      if (mounted) setState(() => _sendingNotification = false);
    }
  }

  Widget _adminNotificationsPage() => Scaffold(
    appBar: _appBar('Push notifications'),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const Text('Send a customer push notification', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text(
          'Send an announcement from Admin. The Customer app must have been opened at least once and the user must allow notifications. When the app is closed, Android can display Firebase notification messages in the notification shade.',
          style: TextStyle(color: Color(0xFF68736D), height: 1.45),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          value: _notificationAudience,
          decoration: const InputDecoration(labelText: 'Audience', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'all_customers', child: Text('All opted-in customers')),
            DropdownMenuItem(value: 'specific_user', child: Text('One customer (user UUID)')),
          ],
          onChanged: _sendingNotification ? null : (value) {
            if (value != null) setState(() {
              _notificationAudience = value;
              _notificationResult = null;
            });
          },
        ),
        if (_notificationAudience == 'specific_user') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _notificationUserIdController,
            enabled: !_sendingNotification,
            decoration: const InputDecoration(
              labelText: 'Customer user UUID',
              hintText: 'Customer account ID',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _notificationTitleController,
          enabled: !_sendingNotification,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Notification title', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notificationBodyController,
          enabled: !_sendingNotification,
          maxLength: 1000,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _sendingNotification ? null : _sendAdminPushNotification,
          icon: _sendingNotification
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          label: Text(_sendingNotification ? 'Sending…' : 'Send notification'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        if (_notificationResult != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE1F2E9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFB8DDC8)),
            ),
            child: Text(_notificationResult!, style: const TextStyle(height: 1.45)),
          ),
        ],
        const SizedBox(height: 18),
        const Text(
          'Notifications can be sent only after secure delivery is configured and at least one Customer device has registered. Send a test notification before broadcasting.',
          style: TextStyle(color: Color(0xFF68736D), fontSize: 12, height: 1.45),
        ),
      ],
    ),
  );

  void _openServiceAreaSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Service Areas & Availability')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: const [AdminServiceConfigPanel()],
          ),
        ),
      ),
    ));
  }

  Widget _adminModulesPage() => Scaffold(
    appBar: _appBar('Admin modules'),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        const Text('Operations control centre', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Open the tools you need. Approval, service availability and pricing changes are validated before taking effect.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
        const SizedBox(height: 16),
        _adminModuleTile(
          Icons.location_on_rounded,
          'Service Areas & Availability',
          'Register PIN codes, enable services per area and configure validated pricing.',
          _openServiceAreaSettings,
        ),
        _adminModuleTile(
          Icons.inventory_2_rounded,
          'Catalogue & banners',
          'Review seller listings and manage the Customer homepage carousel.',
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _adminCataloguePage())),
        ),
        _adminModuleTile(
          Icons.groups_rounded,
          'Partners & approvals',
          'Review applications and manage sellers, drivers, delivery partners and dark stores.',
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _adminPartnersPage())),
        ),
        _adminModuleTile(
          Icons.notifications_active_outlined,
          'Notifications',
          'Send an authorised notification and review the result returned by the sending service.',
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _adminNotificationsPage())),
        ),
        _adminModuleTile(
          Icons.support_agent_rounded,
          'Support & escalations',
          'Review open customer requests, update status and find unresolved issues on the operations dashboard.',
          () => setState(() => selectedTab = 0),
        ),
      ],
    ),
  );

  Widget _adminModuleTile(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    elevation: 0,
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(17),
      side: const BorderSide(color: Color(0xFFDCE6DF)),
    ),
    child: ListTile(
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE1F2E9),
        child: Icon(icon, color: const Color(0xFF176B57)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle, style: const TextStyle(height: 1.35)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );

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
      const SizedBox(height: 16),
      Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFDCE6DF))),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.location_on_rounded, color: Color(0xFF176B57))),
          title: const Text('Service Areas & Availability', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('Manage PIN codes, per-service coverage and local pricing.'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _openServiceAreaSettings,
        ),
      ),
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
      _roleRequestsSection(),
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
      const SizedBox(height: 22),
      const Text('Customer support requests', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: client.from('support_tickets').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, s) {
          if (s.hasError) return _error('Support requests are unavailable right now.');
          if (!s.hasData) return const LinearProgressIndicator();
          if (s.data!.isEmpty) return _empty('No support requests', 'Customer requests will appear here when submitted.');
          return Column(children: s.data!.take(30).map((ticket) {
            final status = ticket['status']?.toString() ?? 'open';
            final created = DateTime.tryParse(ticket['created_at']?.toString() ?? '');
            final date = created == null ? '' : created.day.toString().padLeft(2, '0') + '/' + created.month.toString().padLeft(2, '0') + '/' + created.year.toString();
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 9),
              child: ListTile(
                isThreeLine: true,
                title: Text(ticket['subject']?.toString() ?? 'Support request', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text((ticket['message']?.toString() ?? '') + '\n' + date + ' · ' + status.replaceAll('_', ' '), maxLines: 4, overflow: TextOverflow.ellipsis),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Update request status',
                  onSelected: (value) async {
                    try {
                      await client.rpc('admin_set_support_ticket_status', params: {'p_ticket_id': ticket['id'], 'p_status': value});
                      notice('Support request marked ' + value.replaceAll('_', ' ') + '.');
                    } catch (_) {
                      notice('Could not update the support request. Please retry.');
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(value: 'in_progress', child: Text('In progress')),
                    PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                    PopupMenuItem(value: 'closed', child: Text('Closed')),
                  ],
                  child: Chip(label: Text(status.replaceAll('_', ' '))),
                ),
              ),
            );
          }).toList());
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
          return Column(children: s.data!.take(20).map(_productApprovalTile).toList());
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



  Future<String> _ensureAdminCatalogSellerId() async {
    final result = await client.rpc('admin_ensure_platform_seller');
    final id = result?.toString() ?? '';
    if (id.isEmpty) throw StateError('Could not prepare the Alteo Official Store catalogue.');
    return id;
  }

  Widget _adminCataloguePage() => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Catalogue management'),
        actions: [
          IconButton(tooltip: 'Log out', onPressed: () => confirmAlteoLogout(context, onConfirm: widget.onSignOut), icon: const Icon(Icons.logout_rounded)),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Items'),
            Tab(icon: Icon(Icons.view_carousel_outlined), text: 'Banners'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _adminItemsBody(),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              const Text('Customer homepage banners', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text(
                'Upload banner images, then create, edit, reorder, publish or remove banners. Published changes appear automatically in the Customer app.',
                style: TextStyle(color: Color(0xFF68736D), height: 1.45),
              ),
              const SizedBox(height: 18),
              _bannerManagement(),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _adminItemsBody() => FutureBuilder<String>(
    future: _adminCatalogSellerFuture ??= _ensureAdminCatalogSellerId(),
    builder: (context, sellerSnapshot) {
      if (sellerSnapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 12),
                const Text('Could not open the catalogue', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('The catalogue could not load. Check your connection and admin access, then try again.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => setState(() => _adminCatalogSellerFuture = null),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      }
      if (!sellerSnapshot.hasData) return const Center(child: CircularProgressIndicator());
      final platformSellerId = sellerSnapshot.data!;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer items', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text('Review and manage marketplace product listings.', style: TextStyle(color: Color(0xFF68736D))),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _editAdminProduct(platformSellerId),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Approved items appear in the Customer catalogue. Upload a clear product image no larger than 5 MB.',
            style: TextStyle(color: Color(0xFF68736D), height: 1.45),
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: client.from('seller_products').stream(primaryKey: ['id']).order('created_at', ascending: false),
            builder: (context, s) {
              if (s.hasError) return _error('Items unavailable. Check the admin catalogue permissions.');
              if (!s.hasData) return const LinearProgressIndicator();
              if (s.data!.isEmpty) {
                return _empty('No items yet', 'Tap Add item to create your first Customer catalogue listing.');
              }
              return Column(
                children: s.data!.map((product) {
                  final status = product['status']?.toString() ?? 'draft';
                  final kind = product['kind']?.toString() ?? 'shopping';
                  final price = ((product['price_minor'] as num?)?.toInt() ?? 0) / 100;
                  final imageUrl = product['image_url']?.toString() ?? '';
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 72,
                          height: 76,
                          child: imageUrl.startsWith('https://')
                            ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, size: 30))
                            : Container(
                                color: const Color(0xFFFFF4E5),
                                child: const Icon(Icons.add_photo_alternate_outlined, size: 30, color: Color(0xFF9A5C13)),
                              ),
                        ),
                      ),
                      title: Text(product['name']?.toString() ?? 'Item', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text((product['description']?.toString().trim().isNotEmpty ?? false)
                              ? product['description'].toString()
                              : 'Description missing — add before publishing.',
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('₹' + price.toStringAsFixed(2) + ' · ' + kind.toUpperCase() + ' · ' + status.toUpperCase()),
                            const SizedBox(height: 3),
                            Text(imageUrl.startsWith('https://') ? 'Image attached' : 'Image required before publishing',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                                color: imageUrl.startsWith('https://') ? const Color(0xFF176B57) : const Color(0xFFB3261E))),
                          ],
                        ),
                      ),
                      trailing: Wrap(
                        spacing: 0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PopupMenuButton<String>(
                            tooltip: 'Change listing status',
                            icon: const Icon(Icons.visibility_outlined),
                            onSelected: (value) => _setAdminProductStatus(product, value),
                            itemBuilder: (context) => [
                              for (final state in const ['draft', 'active', 'paused', 'rejected'])
                                PopupMenuItem<String>(
                                  value: state,
                                  enabled: state != 'active' || imageUrl.startsWith('https://'),
                                  child: Row(
                                    children: [
                                      if (state == status) const Icon(Icons.check_rounded, size: 18),
                                      if (state == status) const SizedBox(width: 6),
                                      Text(state[0].toUpperCase() + state.substring(1)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Edit item',
                            onPressed: () => _editAdminProduct(platformSellerId, product),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      );
    },
  );

  Future<void> _setAdminProductStatus(Map<String, dynamic> product, String status) async {
    try {
      await client.rpc('admin_set_product_status', params: {
        'p_product_id': product['id'],
        'p_status': status,
      });
      notice(status == 'active' ? 'Item published to the Customer catalogue.' : 'Item status changed to ' + status + '.');
    } catch (e) {
      debugPrint('Catalog status update failed (${e.runtimeType}).');
      notice('Could not update the listing status. Please retry.');
    }
  }

  Future<void> _editAdminProduct(String platformSellerId, [Map<String, dynamic>? existing]) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final description = TextEditingController(text: existing?['description']?.toString() ?? '');
    final price = TextEditingController(
      text: existing == null ? '' : (((existing['price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2),
    );
    final image = TextEditingController(text: existing?['image_url']?.toString() ?? '');
    var kind = existing?['kind']?.toString() ?? 'shopping';
    var status = existing?['status']?.toString() ?? 'active';
    var uploading = false;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dc) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'Add catalogue item' : 'Edit catalogue item'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      maxLength: 180,
                      decoration: const InputDecoration(labelText: 'Item name *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: kind,
                      decoration: const InputDecoration(labelText: 'Catalogue section', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'shopping', child: Text('Shopping')),
                        DropdownMenuItem(value: 'food', child: Text('Food')),
                        DropdownMenuItem(value: 'quick', child: Text('Quick commerce')),
                      ],
                      onChanged: (value) { if (value != null) setDialogState(() => kind = value); },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: description,
                      maxLength: 4000,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Price in rupees *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: image,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Item image URL * (upload an image below)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: uploading ? null : () async {
                          try {
                            final selected = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 86,
                              maxWidth: 1800,
                            );
                            if (selected == null) return;
                            setDialogState(() => uploading = true);
                            final url = await _uploadCatalogImage(selected);
                            setDialogState(() => image.text = url);
                            notice('Item image uploaded successfully.');
                          } catch (e) {
                            debugPrint('Catalog image upload failed (${e.runtimeType}).');
      notice('Image upload failed. Check the image type, file size and connection, then retry.');
                          } finally {
                            setDialogState(() => uploading = false);
                          }
                        },
                        icon: uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_outlined),
                        label: Text(uploading ? 'Uploading image…' : 'Choose and upload image'),
                      ),
                    ),
                    if (image.text.startsWith('https://')) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          image.text,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(height: 60, child: Center(child: Text('Image preview unavailable'))),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Listing status', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Active — show to customers')),
                        DropdownMenuItem(value: 'draft', child: Text('Draft')),
                        DropdownMenuItem(value: 'paused', child: Text('Paused')),
                        DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                      ],
                      onChanged: (value) { if (value != null) setDialogState(() => status = value); },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: uploading ? null : () => Navigator.pop(dc, true),
                child: Text(existing == null ? 'Add item' : 'Save changes'),
              ),
            ],
          ),
        ),
      );
      if (saved != true) return;

      final itemName = name.text.trim();
      final amount = double.tryParse(price.text.trim());
      final imageUrl = image.text.trim();
      if (itemName.length < 2 || amount == null || amount <= 0) {
        notice('Enter an item name and a price greater than zero.');
        return;
      }
      if (description.text.trim().length < 3) {
        notice('A clear item description is required.');
        return;
      }
      if (!imageUrl.startsWith('https://')) {
        notice('A product image is mandatory. Upload or select an image before saving.');
        return;
      }

      final payload = <String, dynamic>{
        'name': itemName,
        'kind': kind,
        'description': description.text.trim().isEmpty ? null : description.text.trim(),
        'price_minor': (amount * 100).round(),
        'image_url': imageUrl.isEmpty ? null : imageUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (existing == null) {
        payload['seller_id'] = platformSellerId;
        payload['status'] = status;
        payload['currency'] = 'INR';
        await client.from('seller_products').insert(payload);
        notice(status == 'active' ? 'Item added and published to the Customer catalogue.' : 'Item saved as a draft.');
      } else {
        await client.from('seller_products').update(payload).eq('id', existing['id']);
        final originalStatus = existing['status']?.toString() ?? 'draft';
        if (status != originalStatus) {
          await client.rpc('admin_set_product_status', params: {
            'p_product_id': existing['id'],
            'p_status': status,
          });
        }
        notice('Item updated.');
      }
    } catch (e) {
      debugPrint('Catalog item save failed (${e.runtimeType}).');
      notice('Could not save the listing. Check the required fields and try again.');
    } finally {
      name.dispose();
      description.dispose();
      price.dispose();
      image.dispose();
    }
  }

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
      const AdminServiceConfigPanel(),
      const SizedBox(height: 24),
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
      _roleRequestsSection(),
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
          return Column(children: s.data!.take(30).map(_productApprovalTile).toList());
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
          TextField(controller: image, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Image HTTPS URL', border: OutlineInputBorder())),
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
      debugPrint('Product save failed (${e.runtimeType}).');
      notice('Could not save the product. Check the required fields and try again.');
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

  String selectedAreaCode = 'DEFAULT';
  String areaSearchQuery = '';
  bool savingArea = false;

  void message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  bool _isPincode(String value) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(value);

  Future<Map<String, String>?> _lookupPincode(String pin) async {
    if (!_isPincode(pin)) {
      message('Enter a valid 6-digit Indian PIN code first.');
      return null;
    }
    try {
      final response = await http.get(Uri.https('api.postalpincode.in', '/pincode/$pin'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        message('We could not look up that PIN code. You can enter the area details manually.');
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
        message('No postal details were returned. Enter the area details manually.');
        return null;
      }
      final first = Map<String, dynamic>.from(decoded.first as Map);
      final offices = first['PostOffice'];
      if (first['Status']?.toString().toLowerCase() != 'success' || offices is! List || offices.isEmpty || offices.first is! Map) {
        message('That PIN code was not found. Check the digits and try again.');
        return null;
      }
      final office = Map<String, dynamic>.from(offices.first as Map);
      return <String, String>{
        'locality': office['Name']?.toString() ?? '',
        'district': office['District']?.toString() ?? '',
        'state': office['State']?.toString() ?? '',
      };
    } catch (_) {
      message('Postal lookup is unavailable. You can still save the PIN code and enter its details manually.');
      return null;
    }
  }

  Future<void> editServiceArea([Map<String, dynamic>? existing]) async {
    final pin = TextEditingController(text: existing?['pincode']?.toString() ?? '');
    final locality = TextEditingController(text: existing?['locality']?.toString() ?? '');
    final district = TextEditingController(text: existing?['district']?.toString() ?? '');
    final state = TextEditingController(text: existing?['state']?.toString() ?? '');
    var active = existing?['active'] as bool? ?? true;
    var lookingUp = false;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'Add serviceable PIN code' : 'Edit service area'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: pin,
                    enabled: existing == null,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'PIN code *',
                      hintText: '6 digits',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: lookingUp || existing != null ? null : () async {
                        setDialogState(() => lookingUp = true);
                        final details = await _lookupPincode(pin.text.trim());
                        if (details != null) {
                          setDialogState(() {
                            if (locality.text.trim().isEmpty) locality.text = details['locality'] ?? '';
                            if (district.text.trim().isEmpty) district.text = details['district'] ?? '';
                            if (state.text.trim().isEmpty) state.text = details['state'] ?? '';
                          });
                        }
                        setDialogState(() => lookingUp = false);
                      },
                      icon: lookingUp
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search_rounded),
                      label: Text(lookingUp ? 'Looking up PIN code…' : 'Find area details'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(controller: locality, maxLength: 100, decoration: const InputDecoration(labelText: 'Locality / post office', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: district, maxLength: 100, decoration: const InputDecoration(labelText: 'District', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: state, maxLength: 100, decoration: const InputDecoration(labelText: 'State', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Serviceable'),
                    subtitle: const Text('Customers can use services enabled for this PIN code.'),
                    value: active,
                    onChanged: (value) => setDialogState(() => active = value),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Adding a PIN code does not automatically enable every service. Configure shopping, food, quick commerce, parcels and rides separately below.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF68736D)),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: lookingUp ? null : () => Navigator.pop(dialogContext, true), child: const Text('Save PIN code')),
            ],
          ),
        ),
      );
      if (saved != true) return;
      final code = pin.text.trim();
      if (!_isPincode(code)) {
        message('Enter a valid 6-digit Indian PIN code.');
        return;
      }
      setState(() => savingArea = true);
      final payload = <String, dynamic>{
        'pincode': code,
        'locality': locality.text.trim().isEmpty ? null : locality.text.trim(),
        'district': district.text.trim().isEmpty ? null : district.text.trim(),
        'state': state.text.trim().isEmpty ? null : state.text.trim(),
        'active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (existing == null) {
        payload['created_by'] = client.auth.currentUser?.id;
        await client.from('service_areas').insert(payload);
      } else {
        await client.from('service_areas').update(payload).eq('id', existing['id']);
      }
      if (mounted) setState(() => selectedAreaCode = code);
      message(active ? 'PIN code $code is now serviceable. Configure its services below.' : 'PIN code $code is disabled.');
    } catch (e) {
      message('Could not save the service area. Check that the PIN code is not already listed and retry.');
    } finally {
      pin.dispose();
      locality.dispose();
      district.dispose();
      state.dispose();
      if (mounted) setState(() => savingArea = false);
    }
  }

  Future<void> removeServiceArea(Map<String, dynamic> area) async {
    final code = area['pincode']?.toString() ?? '';
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove service area?'),
        content: Text('Remove PIN code $code from the service-area list? Existing service and pricing rules must be absent so configuration is not orphaned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final controls = await client.from('service_controls').select('id').eq('area_code', code).limit(1);
      final prices = await client.from('pricing_rules').select('id').eq('city_code', code).limit(1);
      if ((controls as List).isNotEmpty || (prices as List).isNotEmpty) {
        message('This PIN code has service or pricing rules. Deactivate it instead to preserve those settings and their audit history.');
        return;
      }
      await client.from('service_areas').delete().eq('id', area['id']);
      if (mounted && selectedAreaCode == code) setState(() => selectedAreaCode = 'DEFAULT');
      message('PIN code $code removed.');
    } catch (_) {
      message('Could not remove this PIN code. Deactivate it instead or retry.');
    }
  }

  Future<void> setAreaActive(Map<String, dynamic> area, bool active) async {
    try {
      await client.from('service_areas').update({
        'active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', area['id']);
      message(active
          ? 'PIN code ${area['pincode']} is serviceable again.'
          : 'PIN code ${area['pincode']} is disabled. Checkout and ride quotes will reject this PIN code.');
    } catch (_) {
      message('Could not update this PIN code. Please try again.');
    }
  }

  Future<void> setControl(String service, bool enabled, bool automatic) async {
    try {
      if (selectedAreaCode != 'DEFAULT') {
        final area = await client.from('service_areas')
            .select('active').eq('pincode', selectedAreaCode).maybeSingle();
        if (area == null || area['active'] != true) {
          message('Activate this PIN code before changing its service settings.');
          return;
        }
      }
      if (enabled) {
        final exactPrice = await client.from('pricing_rules')
            .select('id').eq('service', service).eq('city_code', selectedAreaCode)
            .eq('active', true).maybeSingle();
        if (exactPrice == null && selectedAreaCode != 'DEFAULT') {
          final defaultPrice = await client.from('pricing_rules')
              .select('id').eq('service', service).eq('city_code', 'DEFAULT')
              .eq('active', true).maybeSingle();
          if (defaultPrice == null) {
            message('Add active pricing for ${services[service]} or configure DEFAULT pricing before enabling it.');
            return;
          }
        } else if (exactPrice == null) {
          message('Configure active pricing for ${services[service]} before enabling it.');
          return;
        }
      }
      await client.rpc('admin_set_service_control', params: {
        'p_area_code': selectedAreaCode,
        'p_service': service,
        'p_enabled': enabled,
        'p_automatic_assignment': automatic,
      });
      message('${services[service]} settings saved for ${selectedAreaCode == 'DEFAULT' ? 'the default area' : 'PIN code $selectedAreaCode'}.');
    } catch (_) {
      message('Could not update service settings. Check that the PIN code is active and try again.');
    }
  }

  Future<void> editPricing(String service, Map<String, dynamic>? existing) async {
    final base = TextEditingController(text: (((existing?['base_fee_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0));
    final perKm = TextEditingController(text: (((existing?['per_km_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0));
    final minimum = TextEditingController(text: (((existing?['minimum_fee_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0));
    var active = existing?['active'] as bool? ?? true;
    try {
      final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Pricing · ${selectedAreaCode == 'DEFAULT' ? 'DEFAULT' : selectedAreaCode} · ${services[service]}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: base, keyboardType: const TextInputType.numberWithOptions(decimal: false), decoration: const InputDecoration(labelText: 'Base charge (₹)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: perKm, keyboardType: const TextInputType.numberWithOptions(decimal: false), decoration: const InputDecoration(labelText: 'Additional charge per km (₹)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: false), decoration: const InputDecoration(labelText: 'Minimum charge (₹)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Pricing active'), value: active, onChanged: (v) => setDialogState(() => active = v)),
            const SizedBox(height: 8),
            const Text('These values are used by server-side checkout or ride quoting. Leave automatic assignment off until partners and dispatch are ready.', style: TextStyle(color: Color(0xFF68736D), height: 1.4, fontSize: 12)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save pricing')),
          ],
        ),
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
        'city_code': selectedAreaCode,
        'base_fee_minor': b * 100,
        'per_km_minor': k * 100,
        'minimum_fee_minor': m * 100,
        'active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'service,city_code');
      message('Pricing saved for ${services[service]} · ${selectedAreaCode == 'DEFAULT' ? 'DEFAULT' : selectedAreaCode}.');
    } catch (_) {
      message('Could not save pricing. Check the amount fields and try again.');
    } finally {
      base.dispose();
      perKm.dispose();
      minimum.dispose();
    }
  }

  Widget _serviceControls(
    List<Map<String, dynamic>> allControls,
    List<Map<String, dynamic>> allPrices,
    bool selectedAreaActive,
  ) {
    final controls = <String, Map<String, dynamic>>{
      for (final row in allControls)
        '${row['area_code']}|${row['service']}': row,
    };
    final prices = <String, Map<String, dynamic>>{
      for (final row in allPrices)
        '${row['city_code']}|${row['service']}': row,
    };
    return Column(children: services.entries.map((entry) {
      final service = entry.key;
      final exactControl = controls['$selectedAreaCode|$service'];
      final control = exactControl ?? controls['DEFAULT|$service'];
      final isInherited = selectedAreaCode != 'DEFAULT' && exactControl == null && control != null;
      final enabled = control?['enabled'] as bool? ?? false;
      final automatic = control?['automatic_assignment'] as bool? ?? false;
      final exactPrice = prices['$selectedAreaCode|$service'];
      final price = exactPrice ?? (selectedAreaCode == 'DEFAULT' ? null : prices['DEFAULT|$service']);
      final activePrice = price?['active'] as bool? ?? false;
      final inheritedPrice = selectedAreaCode != 'DEFAULT' && exactPrice == null && price != null;
      final priceLabel = price == null
          ? 'Pricing not configured'
          : 'Base ₹${(((price['base_fee_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)}'
            + ' · /km ₹${(((price['per_km_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)}'
            + ' · Minimum ₹${(((price['minimum_fee_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)}'
            + (activePrice ? '' : ' · inactive')
            + (inheritedPrice ? ' · DEFAULT rate' : '');
      final canEditArea = selectedAreaCode == 'DEFAULT' || selectedAreaActive;
      return Card(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(isInherited
                  ? '${enabled ? 'Enabled' : 'Disabled'} by DEFAULT rules · save to override this PIN'
                  : enabled
                    ? 'Enabled for ${selectedAreaCode == 'DEFAULT' ? 'DEFAULT area' : 'PIN $selectedAreaCode'}'
                    : 'Disabled for ${selectedAreaCode == 'DEFAULT' ? 'DEFAULT area' : 'PIN $selectedAreaCode'}'),
              value: enabled,
              onChanged: canEditArea ? (value) => setControl(service, value, automatic) : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic assignment'),
              subtitle: const Text('Off keeps assignment under Admin control'),
              value: automatic,
              onChanged: canEditArea ? (value) => setControl(service, enabled, value) : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pricing'),
              subtitle: Text(priceLabel),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Configure pricing',
                onPressed: canEditArea ? () => editPricing(service, exactPrice ?? price) : null,
              ),
            ),
          ]),
        ),
      );
    }).toList());
  }

  Widget _serviceAreaManager(List<Map<String, dynamic>> areas) {
    final filteredAreas = areas.where((area) {
      final haystack = [area['pincode'], area['locality'], area['district'], area['state']]
          .where((part) => part != null).join(' ').toLowerCase();
      return haystack.contains(areaSearchQuery.trim().toLowerCase());
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Serviceable PIN codes', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          SizedBox(height: 4),
          Text('Add a PIN code once. Alteo uses it to check area coverage for each enabled service.', style: TextStyle(fontSize: 12, color: Color(0xFF68736D), height: 1.4)),
        ])),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: savingArea ? null : () => editServiceArea(),
          icon: savingArea ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_location_alt_rounded),
          label: const Text('Add PIN'),
        ),
      ]),
      const SizedBox(height: 10),
      TextField(
        onChanged: (value) => setState(() => areaSearchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search PIN code, locality, district or state',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: areaSearchQuery.isEmpty ? null : IconButton(
            tooltip: 'Clear search',
            onPressed: () => setState(() => areaSearchQuery = ''),
            icon: const Icon(Icons.clear_rounded),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      const SizedBox(height: 8),
      if (areas.isEmpty)
        const Card(elevation: 0, child: Padding(padding: EdgeInsets.all(16), child: Text('No PIN codes added yet. Add your first service area to enable PIN-level controls.')))
      else if (filteredAreas.isEmpty)
        const Card(elevation: 0, child: Padding(padding: EdgeInsets.all(16), child: Text('No matching service areas. Try another PIN code or locality.')))
      else
        ...filteredAreas.map((area) {
          final code = area['pincode']?.toString() ?? '';
          final active = area['active'] == true;
          final label = [
            area['locality'], area['district'], area['state'],
          ].where((part) => part != null && part.toString().trim().isNotEmpty).join(' · ');
          return Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 7),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: active ? const Color(0xFFE1F2E9) : const Color(0xFFFFE8E6),
                child: Icon(Icons.location_on_outlined, color: active ? const Color(0xFF176B57) : const Color(0xFFB3261E)),
              ),
              title: Text(code, style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(label.isEmpty ? (active ? 'Serviceable' : 'Disabled') : '$label · ${active ? 'Serviceable' : 'Disabled'}'),
              onTap: () => setState(() => selectedAreaCode = code),
              trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                PopupMenuButton<String>(
                  tooltip: 'Service-area actions',
                  onSelected: (action) {
                    if (action == 'edit') editServiceArea(area);
                    if (action == 'remove') removeServiceArea(area);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit details'), contentPadding: EdgeInsets.zero)),
                    PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Remove PIN code'), contentPadding: EdgeInsets.zero)),
                  ],
                ),
                Switch(value: active, onChanged: (value) => setAreaActive(area, value)),
              ]),
            ),
          );
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: client.from('service_areas').stream(primaryKey: ['id']).order('pincode'),
    builder: (context, areaSnapshot) {
      if (areaSnapshot.hasError) return const Text('PIN-code settings are unavailable. Check the admin account and connection.');
      if (!areaSnapshot.hasData) return const LinearProgressIndicator();
      final areas = areaSnapshot.data!;
      final selectedArea = areas.where((row) => row['pincode']?.toString() == selectedAreaCode).toList();
      final selectedAreaActive = selectedArea.isNotEmpty && selectedArea.first['active'] == true;
      if (selectedAreaCode != 'DEFAULT' && selectedArea.isEmpty && areas.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !areas.any((row) => row['pincode']?.toString() == selectedAreaCode)) {
            setState(() => selectedAreaCode = 'DEFAULT');
          }
        });
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Service availability & pricing', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('Control the PIN codes where Alteo operates, then choose which services are available in each area. Changes apply without releasing a new app build.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
        const SizedBox(height: 16),
        _serviceAreaManager(areas),
        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 8),
        const Text('Configure services', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedAreaCode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Area to configure', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: 'DEFAULT', child: Text('DEFAULT · Global fallback')),
            ...areas.map((area) => DropdownMenuItem(
              value: area['pincode']?.toString(),
              child: Text('${area['pincode']} · ${area['locality'] ?? area['district'] ?? area['state'] ?? (area['active'] == true ? 'Service area' : 'Disabled')}' ,
                overflow: TextOverflow.ellipsis),
            )),
          ],
          onChanged: (value) {
            if (value != null) setState(() => selectedAreaCode = value);
          },
        ),
        if (selectedAreaCode != 'DEFAULT' && !selectedAreaActive)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('This PIN code is inactive. Activate it before enabling its services.', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 10),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: client.from('service_controls').stream(primaryKey: ['id']),
          builder: (context, controlSnapshot) => StreamBuilder<List<Map<String, dynamic>>>(
            stream: client.from('pricing_rules').stream(primaryKey: ['id']),
            builder: (context, priceSnapshot) {
              if (controlSnapshot.hasError || priceSnapshot.hasError) return const Text('Service settings unavailable. Try again or check admin permissions.');
              if (!controlSnapshot.hasData || !priceSnapshot.hasData) return const LinearProgressIndicator();
              return _serviceControls(controlSnapshot.data!, priceSnapshot.data!, selectedAreaActive);
            },
          ),
        ),
      ]);
    },
  );
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
