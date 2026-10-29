import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alteo_notifications/alteo_notifications.dart';
import 'package:alteo_partner_ui/alteo_partner_ui.dart';

const appName = 'Alteo Driver Partner';
const requiredRole = 'driver_partner';
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
    // Public exploration should remain available when sign-in or live services are unavailable.
  }
  if (backendReady) {
    unawaited(AlteoPushNotifications.instance.initialize(
      client: Supabase.instance.client,
      appId: 'driver_partner',
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
      builder: (context, child) => AlteoFirstLaunchPermissionGate(
        appId: 'driver_partner',
        child: child ?? const SizedBox.shrink(),
      ),
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
  bool onboardingRequired = false;
  Map<String, dynamic>? onboardingRequest;
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
      final row = await client.from('user_roles').select('role').eq('user_id', current.id).eq('role', requiredRole).maybeSingle();
      if (!mounted) return;
      if (row != null) {
        // Ensure approved accounts have the role-specific workspace record before opening the dashboard.
        await client.rpc('ensure_current_partner_profile', params: {'p_role': requiredRole})
          .timeout(const Duration(seconds: 12));
        if (!mounted) return;
        setState(() { authorized = true; onboardingRequired = false; onboardingRequest = null; message = 'Access verified.'; });
        if (authSheetOpen && mounted) Navigator.of(context).maybePop();
        return;
      }
      final request = await client.from('role_requests').select('*').eq('user_id', current.id).eq('requested_role', requiredRole).maybeSingle();
      if (!mounted) return;
      if (request == null || request['status'] == 'rejected' ||
          (request['status'] == 'pending' && request['needs_correction'] == true)) {
        setState(() { authorized = false; onboardingRequired = true; onboardingRequest = request == null ? null : Map<String,dynamic>.from(request); message = null; });
        if (authSheetOpen && mounted) Navigator.of(context).maybePop();
        return;
      }
      final requestMessage = request['status'] == 'approved'
          ? 'Your request was approved. Refresh access to continue.'
          : 'Your onboarding request is pending Admin review. Protected features unlock after approval.';
      setState(() { authorized = false; onboardingRequired = false; onboardingRequest = Map<String,dynamic>.from(request); message = requestMessage; });
      if (authSheetOpen && mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) setState(() => message = 'Could not verify your onboarding status. Please check your connection and try again.');
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
    if (onboardingRequired && widget.backendReady && Supabase.instance.client.auth.currentUser != null) {
      return PartnerOnboardingPage(role: requiredRole, user: Supabase.instance.client.auth.currentUser!, existingRequest: onboardingRequest, onSubmitted: () { _checkRole(); });
    }
    if (authorized) return RoleOperationsPage(onSignOut: () async { await AlteoPushNotifications.instance.unregisterCurrentDevice(); await Supabase.instance.client.auth.signOut(); if (mounted) setState(() => authorized = false); });
    return Scaffold(
    appBar: AppBar(
      title: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF2463D4), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 22)),
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
                if (widget.backendReady && Supabase.instance.client.auth.currentSession != null) ...[
                  IconButton(
                    tooltip: 'Check approval status',
                    onPressed: busy ? null : () async {
                      setState(() { busy = true; });
                      await _checkRole();
                      if (mounted) setState(() { busy = false; });
                    },
                    icon: busy ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Log out',
                    onPressed: () => confirmAlteoLogout(context, onConfirm: () async {
                      await AlteoPushNotifications.instance.unregisterCurrentDevice(); await Supabase.instance.client.auth.signOut();
                      if (mounted) setState(() { authorized = false; onboardingRequired = false; onboardingRequest = null; message = null; });
                    }),
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ],
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
        AlteoPartnerPublicProfileCard(appName: appName, role: requiredRole),
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
  final roleUserId = TextEditingController();
  String grantRole = 'delivery_partner';
  bool partnerOnline = false;
  Timer? locationUpdateTimer;
  bool locationUpdateInFlight = false;
  String? partnerAreaCode;
  List<Map<String, dynamic>> partnerServiceAreas = <Map<String, dynamic>>[];
  double? lastLatitude;
  double? lastLongitude;
  DateTime? lastLocationAt;
  bool refreshingLocation = false;
  int selectedTab = 0;

  @override
  void initState() {
    super.initState();
    metrics = requiredRole == 'admin' ? client.rpc('admin_operations_summary') : Future.value(<String, dynamic>{});
    sellerProfile = requiredRole == 'seller' && user != null
      ? client.from('sellers').select('id,status,display_name').eq('owner_id', user!.id).maybeSingle().timeout(const Duration(seconds: 15))
      : Future.value(null);
    storeProfile = requiredRole == 'dark_store' && user != null
      ? client.from('dark_stores').select('id,status,name,locality').eq('owner_user_id', user!.id).maybeSingle().timeout(const Duration(seconds: 15))
      : Future.value(null);
    if ((requiredRole == 'driver_partner' || requiredRole == 'delivery_partner') && user != null) {
      _loadServiceAreas();
      _loadAvailability();
    }
  }

  @override
  void dispose() {
    locationUpdateTimer?.cancel();
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
      if (mounted && (name == 'driver_update_ride_status' || name == 'partner_update_delivery_status')) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Admin/partner RPC action failed (${e.runtimeType}).');
      notice('We could not complete this action. Check your access and connection, then try again.');
    }
  }


  Future<void> _loadServiceAreas() async {
    try {
      final rows = await client.from('service_areas').select('pincode,locality,district,state')
        .eq('active', true).order('pincode');
      if (!mounted) return;
      setState(() {
        partnerServiceAreas = List<Map<String, dynamic>>.from(rows as List);
        if (partnerAreaCode != null && !partnerServiceAreas.any((a) => a['pincode']?.toString() == partnerAreaCode)) {
          partnerAreaCode = null;
        }
      });
    } catch (_) {
      if (mounted) notice('Could not load active service PINs. Contact Admin if the list remains empty.');
    }
  }

  Future<void> _loadAvailability() async {
    try {
      final row = await client.from('partner_presence')
        .select('is_online,area_code,latitude,longitude,updated_at')
        .eq('user_id', user!.id).eq('role', requiredRole).maybeSingle();
      if (!mounted) return;
      final code = row?['area_code']?.toString();
      setState(() {
        partnerOnline = row?['is_online'] as bool? ?? false;
        partnerAreaCode = code != null && RegExp(r'^[1-9][0-9]{5}$').hasMatch(code) ? code : null;
        lastLatitude = (row?['latitude'] as num?)?.toDouble();
        lastLongitude = (row?['longitude'] as num?)?.toDouble();
        lastLocationAt = DateTime.tryParse(row?['updated_at']?.toString() ?? '')?.toLocal();
      });
      if (partnerOnline) {
        _startLocationUpdates();
        unawaited(_shareCurrentLocation(showNotice: false));
      } else {
        _stopLocationUpdates();
      }
    } catch (_) {}
  }

  Future<void> _savePartnerArea(String pin) async {
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)
        || !partnerServiceAreas.any((a) => a['pincode']?.toString() == pin)) {
      notice('Choose an active six-digit PIN from the list.');
      return;
    }
    try {
      await client.rpc('partner_set_availability', params: {
        'p_role': requiredRole, 'p_area_code': pin, 'p_is_online': false,
        'p_latitude': lastLatitude, 'p_longitude': lastLongitude,
      }).timeout(const Duration(seconds: 12));
      _stopLocationUpdates();
      if (mounted) setState(() { partnerAreaCode = pin; partnerOnline = false; });
      notice('Service PIN saved. Go online when you are ready for work.');
    } catch (_) {
      notice('Could not save that PIN. Confirm it is active in Admin > Service Areas.');
    }
  }

  Future<void> _setAvailability() async {
    final next = !partnerOnline;
    double? latitude;
    double? longitude;
    if (next && (partnerAreaCode == null ||
        !partnerServiceAreas.any((a) => a['pincode']?.toString() == partnerAreaCode))) {
      notice('Choose an active service PIN before going online.');
      return;
    }
    try {
      if (next) {
        if (!await Geolocator.isLocationServiceEnabled()) {
          notice('Turn on Location to go online and receive nearby assignments.');
          return;
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          notice('Allow location access to go online.');
          return;
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
        );
        latitude = pos.latitude;
        longitude = pos.longitude;
      }
      await client.rpc('partner_set_availability', params: {
        'p_role': requiredRole, 'p_area_code': partnerAreaCode ?? 'DEFAULT',
        'p_is_online': next, 'p_latitude': latitude, 'p_longitude': longitude,
      }).timeout(const Duration(seconds: 12));
      if (mounted) setState(() {
        partnerOnline = next;
        if (latitude != null && longitude != null) {
          lastLatitude = latitude;
          lastLongitude = longitude;
          lastLocationAt = DateTime.now();
        }
      });
      if (next) {
        _startLocationUpdates();
        unawaited(_shareCurrentLocation(showNotice: false));
      } else {
        _stopLocationUpdates();
      }
      notice(next ? 'You are online in PIN ' + (partnerAreaCode ?? '') + '.' : 'You are offline. Location sharing has stopped.');
    } catch (_) {
      notice('Availability could not be updated. Check your service PIN and location permission.');
    }
  }

  Future<void> _refreshPartnerLocation() async {
    if (refreshingLocation) return;
    setState(() => refreshingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        notice('Turn on Location services and try again.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        notice('Allow location access to refresh your position.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      if (partnerOnline) {
        await client.rpc('partner_update_location', params: {
          'p_role': requiredRole, 'p_latitude': pos.latitude, 'p_longitude': pos.longitude,
        }).timeout(const Duration(seconds: 10));
      }
      if (!mounted) return;
      setState(() { lastLatitude = pos.latitude; lastLongitude = pos.longitude; lastLocationAt = DateTime.now(); });
      notice(partnerOnline ? 'Location refreshed and shared.' : 'Location refreshed. Go online to share it with dispatch.');
    } catch (_) {
      notice('Could not refresh location. Check GPS and app permissions.');
    } finally {
      if (mounted) setState(() => refreshingLocation = false);
    }
  }

  Future<void> _openCurrentLocationMap() async {
    final target = lastLatitude != null && lastLongitude != null
      ? lastLatitude.toString() + ',' + lastLongitude.toString()
      : (partnerAreaCode ?? '');
    if (target.isEmpty) {
      notice('Refresh your current location or choose a service PIN first.');
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': target});
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) notice('Could not open the map on this device.');
    } catch (_) {
      notice('Could not open the map on this device.');
    }
  }

  String _partnerLocationSummary() {
    if (lastLatitude == null || lastLongitude == null) {
      return 'Current GPS location has not been checked. Tap Refresh location to get your position.';
    }
    final t = lastLocationAt;
    final time = t == null ? '' : ' · updated ' + t.hour.toString().padLeft(2, '0') + ':' + t.minute.toString().padLeft(2, '0');
    return 'GPS ' + lastLatitude!.toStringAsFixed(5) + ', ' + lastLongitude!.toStringAsFixed(5) + time;
  }

  Widget _partnerHomePage() => Scaffold(
    appBar: _appBar(requiredRole == 'driver_partner' ? 'Driver home' : 'Delivery home'),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 28), children: [
      const Text('Welcome back', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      Text(requiredRole == 'driver_partner'
        ? 'Manage your current location, service PIN and ride availability.'
        : 'Manage your current location, service PIN and delivery availability.',
        style: const TextStyle(color: Color(0xFF68736D), height: 1.45)),
      const SizedBox(height: 16),
      AlteoServiceAreaLocationCard(
        role: requiredRole, selectedPin: partnerAreaCode, activeAreas: partnerServiceAreas,
        isOnline: partnerOnline, locationSummary: _partnerLocationSummary(),
        isRefreshingLocation: refreshingLocation,
        onAreaChanged: (pin) { if (pin != null) _savePartnerArea(pin); },
        onRefreshLocation: _refreshPartnerLocation,
        onToggleAvailability: _setAvailability,
        onOpenMap: _openCurrentLocationMap,
      ),
      Card(elevation: 0, child: ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFFE1F2E9),
          child: Icon(requiredRole == 'driver_partner' ? Icons.directions_car_filled_rounded : Icons.local_shipping_rounded, color: const Color(0xFF176B57))),
        title: Text(requiredRole == 'driver_partner' ? 'My rides' : 'My deliveries', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: const Text('Review assigned work and update its status.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => setState(() => selectedTab = 1),
      )),
      Card(elevation: 0, child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF176B57))),
        title: const Text('Earnings', style: TextStyle(fontWeight: FontWeight.w900)),
        subtitle: const Text('Review completed work and earnings information.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => setState(() => selectedTab = 2),
      )),
    ]),
  );

  void _startLocationUpdates() {
    locationUpdateTimer?.cancel();
    locationUpdateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_shareCurrentLocation(showNotice: false));
    });
  }

  void _stopLocationUpdates() {
    locationUpdateTimer?.cancel();
    locationUpdateTimer = null;
  }

  Future<void> _shareCurrentLocation({bool showNotice = true}) async {
    if (locationUpdateInFlight || !partnerOnline || user == null) return;
    locationUpdateInFlight = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (showNotice) notice('Turn on Location services to update your position.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (showNotice) notice('Allow location access in system settings to share live position.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      await client.rpc('partner_update_location', params: {
        'p_role': requiredRole,
        'p_latitude': position.latitude,
        'p_longitude': position.longitude,
      }).timeout(const Duration(seconds: 10));
      if (mounted) setState(() {
        lastLatitude = position.latitude;
        lastLongitude = position.longitude;
        lastLocationAt = DateTime.now();
      });
      if (showNotice) notice('Live location updated.');
    } catch (e) {
      debugPrint('Location update failed (${e.runtimeType}).');
      if (showNotice) notice('We could not update your location. Check location access and try again.');
    } finally {
      locationUpdateInFlight = false;
    }
  }

  Future<void> _openDirections({double? latitude, double? longitude, String? label}) async {
    final destination = latitude != null && longitude != null
        ? latitude.toString() + ',' + longitude.toString()
        : (label ?? '').trim();
    if (destination.isEmpty) {
      notice('Pickup/destination coordinates are not available yet.');
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        notice('Could not open map navigation on this device.');
      }
    } catch (_) {
      notice('Could not open map navigation on this device.');
    }
  }

  PreferredSizeWidget _partnerAppBar(String title) => AppBar(title: Text(title), actions: [
    IconButton(
      tooltip: 'Update live location',
      onPressed: partnerOnline ? () => _shareCurrentLocation() : null,
      icon: const Icon(Icons.my_location_rounded),
    ),
    TextButton.icon(
      onPressed: _setAvailability,
      icon: Icon(partnerOnline ? Icons.toggle_on_rounded : Icons.toggle_off_rounded),
      label: Text(partnerOnline ? 'Online' : 'Go online'),
    ),
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
      'driver_partner' => _driverHomeDashboard(),
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
    if (requiredRole == 'driver_partner' && label == 'Rides') return _driverDashboard();
    if (requiredRole == 'driver_partner' && label == 'Earnings') return _driverEarningsPage();
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
          AlteoPartnerAccountCard(role: requiredRole, userId: user!.id),
          AlteoPartnerRatingCard(role: requiredRole, userId: user!.id),
          AlteoAppUpdateTile(appId: requiredRole),
          AlteoAppLegalTiles(appName: appName),
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
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlteoDevicePermissionsPage(appName: appName))),
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

  PreferredSizeWidget _appBar(String title) => AppBar(title: Text(title));

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


  Widget _driverEarningsPage() => Scaffold(
    appBar: _appBar('Trip earnings'),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: client.from('rides').stream(primaryKey: ['id']).eq('driver_id', user!.id).eq('status', 'completed').order('updated_at', ascending: false),
      builder: (context, s) {
        if (s.hasError) return _error('Completed trips unavailable.');
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final trips = s.data!;
        final total = trips.fold<int>(0, (sum, row) => sum + ((row['fare_minor'] as num?)?.toInt() ?? 0));
        return ListView(padding: const EdgeInsets.all(18), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF2C8B70)]), borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('COMPLETED TRIP FARES', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('₹' + (total / 100).toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
              Text(trips.length.toString() + ' completed trips', style: const TextStyle(color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 10),
          const Text('This is the sum of completed trip fares, not a confirmed payout balance. Settlement records must be enabled separately.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
          const SizedBox(height: 18),
          for (final trip in trips)
            Card(elevation: 0, child: ListTile(
              leading: const Icon(Icons.route_rounded, color: Color(0xFF176B57)),
              title: Text((trip['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (trip['destination_label']?.toString() ?? 'Destination')),
              subtitle: Text('Completed · ' + (trip['updated_at']?.toString() ?? '')),
              trailing: Text('₹' + ((((trip['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)), style: const TextStyle(fontWeight: FontWeight.w900)),
            )),
          if (trips.isEmpty) _empty('No completed trips yet', 'Completed trips and their fare totals will appear here.'),
        ]);
      },
    ),
  );

  Widget _driverHomeDashboard() => Scaffold(
    appBar: _partnerAppBar('Captain dashboard'),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: client.from('rides').select('*').eq('driver_id', user!.id)
          .order('created_at', ascending: false).limit(40)
          .timeout(const Duration(seconds: 15)),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _loadFailure('Your ride dashboard could not load. Check your connection and approved driver access, then retry.', () => setState(() {}));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rides = snapshot.data!;
        final now = DateTime.now();
        final activeRides = rides.where((ride) =>
          !const ['completed', 'cancelled', 'rejected'].contains(ride['status']?.toString())).toList();
        final todayCompleted = rides.where((ride) {
          if (ride['status']?.toString() != 'completed') return false;
          final completedAt = DateTime.tryParse(ride['updated_at']?.toString() ?? '')?.toLocal();
          return completedAt != null && completedAt.year == now.year &&
              completedAt.month == now.month && completedAt.day == now.day;
        }).toList();
        final todayFareMinor = todayCompleted.fold<int>(0,
          (sum, ride) => sum + ((ride['fare_minor'] as num?)?.toInt() ?? 0));
        final requests = rides.where((ride) => ride['status']?.toString() == 'requested').toList();

        Widget metric(String value, String label, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE3E9E5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: const Color(0xFF2463D4), size: 22),
              const SizedBox(height: 9),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF68736D))),
            ]),
          ),
        );

        return RefreshIndicator(
          onRefresh: () async { if (mounted) setState(() {}); },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF163D83), Color(0xFF3476DC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 30),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Drive with Alteo', style: TextStyle(
                      color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(30)),
                      child: Text(partnerOnline ? 'ONLINE' : 'OFFLINE',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    partnerOnline
                      ? 'You are available. New eligible ride requests can be assigned to you.'
                      : 'Go online when you are ready to receive nearby ride requests.',
                    style: const TextStyle(color: Colors.white, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Text(partnerAreaCode == null ? 'No service PIN selected' : 'Service PIN · $partnerAreaCode',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE3E9E5))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Operating area', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 7),
                    if (partnerServiceAreas.isEmpty)
                      const Text('No active service PINs are configured. Contact Admin before going online.',
                        style: TextStyle(color: Color(0xFF68736D), height: 1.4))
                    else
                      DropdownButtonFormField<String>(
                        value: partnerServiceAreas.any((area) => area['pincode']?.toString() == partnerAreaCode)
                            ? partnerAreaCode : null,
                        isExpanded: true,
                        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Service PIN code'),
                        items: partnerServiceAreas.map((area) {
                          final pin = area['pincode']?.toString() ?? '';
                          final locality = area['locality']?.toString().trim() ?? '';
                          final district = area['district']?.toString().trim() ?? '';
                          return DropdownMenuItem<String>(
                            value: pin,
                            child: Text([pin, if (locality.isNotEmpty) locality, if (district.isNotEmpty) district].join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: partnerOnline ? null : (pin) { if (pin != null) unawaited(_savePartnerArea(pin)); },
                      ),
                    if (partnerOnline)
                      const Padding(padding: EdgeInsets.only(top: 7), child: Text(
                        'Go offline before changing your service area.', style: TextStyle(color: Color(0xFF68736D), fontSize: 12))),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE3E9E5))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 15, 16, 4),
                    child: Text('Live location', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  if (lastLatitude != null && lastLongitude != null)
                    SizedBox(
                      height: 230,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(lastLatitude!, lastLongitude!),
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.alteo.alteo_driver_partner',
                          ),
                          MarkerLayer(markers: [
                            Marker(
                              point: LatLng(lastLatitude!, lastLongitude!),
                              width: 54,
                              height: 54,
                              child: Container(
                                decoration: BoxDecoration(color: const Color(0xFF2463D4), borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white, width: 3)),
                                child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 26),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 160,
                      width: double.infinity,
                      color: const Color(0xFFEAF1FB),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.my_location_rounded, color: Color(0xFF2463D4), size: 36),
                        const SizedBox(height: 8),
                        Text(partnerOnline ? 'Waiting for a fresh GPS position…' : 'Your live map appears when location is available.',
                          style: const TextStyle(color: Color(0xFF40516B)), textAlign: TextAlign.center),
                        const SizedBox(height: 5),
                        if (partnerOnline)
                          TextButton.icon(
                            onPressed: () => _shareCurrentLocation(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Refresh location'),
                          ),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Text(
                      lastLocationAt == null ? 'Location has not been shared yet.'
                        : 'Last location update · ${lastLocationAt!.toLocal().toString().substring(0, 16)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF68736D)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                metric('₹${(todayFareMinor / 100).toStringAsFixed(0)}', 'Today’s completed fares', Icons.account_balance_wallet_rounded),
                const SizedBox(width: 8),
                metric(todayCompleted.length.toString(), 'Trips completed today', Icons.task_alt_rounded),
                const SizedBox(width: 8),
                metric(activeRides.length.toString(), 'Open trips', Icons.route_rounded),
              ]),
              const Padding(
                padding: EdgeInsets.only(top: 7, left: 3),
                child: Text('Completed fares are an estimate of trip value, not a confirmed payout balance.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF68736D))),
              ),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: Text('Ride requests & active trips', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
                TextButton(onPressed: () => setState(() => selectedTab = 1), child: const Text('View all')),
              ]),
              if (activeRides.isEmpty)
                _empty('No active rides', partnerOnline
                  ? 'You are online. New eligible assignments will appear here.'
                  : 'Go online to receive eligible requests in your configured service PIN.')
              else
                ...activeRides.take(4).map((ride) {
                  final status = ride['status']?.toString() ?? 'requested';
                  final fare = (((ride['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0);
                  String? action, actionLabel;
                  if (status == 'requested') { action = 'accept'; actionLabel = 'Accept ride'; }
                  if (status == 'accepted') { action = 'arrived'; actionLabel = 'I have arrived'; }
                  if (status == 'arrived') { action = 'start'; actionLabel = 'Start trip'; }
                  if (status == 'in_progress') { action = 'complete'; actionLabel = 'Complete trip'; }
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE3E9E5))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const CircleAvatar(backgroundColor: Color(0xFFEAF1FB), child: Icon(Icons.route_rounded, color: Color(0xFF2463D4))),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((ride['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (ride['destination_label']?.toString() ?? 'Destination'),
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Text('Status · ${status.replaceAll('_', ' ')} · Fare ₹$fare',
                              style: const TextStyle(color: Color(0xFF68736D))),
                          ])),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: OutlinedButton.icon(
                            onPressed: () => _openDirections(
                              latitude: status == 'in_progress' ? (ride['destination_latitude'] as num?)?.toDouble() : (ride['pickup_latitude'] as num?)?.toDouble(),
                              longitude: status == 'in_progress' ? (ride['destination_longitude'] as num?)?.toDouble() : (ride['pickup_longitude'] as num?)?.toDouble(),
                              label: status == 'in_progress' ? ride['destination_label']?.toString() : ride['pickup_label']?.toString(),
                            ),
                            icon: const Icon(Icons.navigation_rounded),
                            label: Text(status == 'in_progress' ? 'Navigate to drop-off' : 'Navigate to pickup'),
                          )),
                          if (action != null) ...[
                            const SizedBox(width: 8),
                            Expanded(child: FilledButton(
                              onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': ride['id'], 'p_action': action}, '${actionLabel!.replaceAll('trip', 'Trip').replaceAll('ride', 'Ride')}.'),
                              child: Text(actionLabel!),
                            )),
                          ],
                        ]),
                      ]),
                    ),
                  );
                }),
              if (requests.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${requests.length} ride request(s) assigned and waiting for your response.',
                    style: const TextStyle(color: Color(0xFF2463D4), fontWeight: FontWeight.w800)),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => setState(() => selectedTab = 2),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('View earnings & completed trips'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _driverDashboard() => Scaffold(
    appBar: _partnerAppBar('My rides'),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: client.from('rides').select('*').eq('driver_id', user!.id)
          .order('created_at', ascending: false).timeout(const Duration(seconds: 15)),
      builder: (context, s) {
        if (s.hasError) return _loadFailure('Rides could not load. Check your connection and approved driver access, then retry.', () => setState(() {}));
        if (!s.hasData) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(), SizedBox(height: 12), Text('Loading your rides…'),
        ]));
        if (s.data!.isEmpty) return _empty('No rides assigned', 'Assigned rides appear here when you are online and eligible for dispatch.');
        return RefreshIndicator(
          onRefresh: () async { setState(() {}); },
          child: ListView(padding: const EdgeInsets.all(16), children: s.data!.map((r) {
            final status = r['status']?.toString() ?? 'requested';
            final buttons = <Widget>[];
            if (status == 'requested') buttons.add(FilledButton(onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': r['id'], 'p_action': 'accept'}, 'Ride accepted.'), child: const Text('Accept')));
            if (status == 'accepted') buttons.add(FilledButton(onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': r['id'], 'p_action': 'arrived'}, 'Marked arrived.'), child: const Text('Arrived')));
            if (status == 'arrived') buttons.add(FilledButton(onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': r['id'], 'p_action': 'start'}, 'Trip started.'), child: const Text('Start trip')));
            if (status == 'in_progress') buttons.add(FilledButton(onPressed: () => rpc('driver_update_ride_status', {'p_ride_id': r['id'], 'p_action': 'complete'}, 'Trip completed.'), child: const Text('Complete')));
            if (status == 'completed') buttons.add(AlteoRateCompletedWorkButton(role: requiredRole, transactionType: 'ride', transactionId: r['id'].toString()));
            return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((r['pickup_label']?.toString() ?? 'Pickup') + ' → ' + (r['destination_label']?.toString() ?? 'Destination'), style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6), Text('Status: ' + status + ' · Fare ₹' + (((r['fare_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0)),
              Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (status != 'in_progress' && status != 'completed')
                  OutlinedButton.icon(
                    onPressed: () => _openDirections(latitude: (r['pickup_latitude'] as num?)?.toDouble(), longitude: (r['pickup_longitude'] as num?)?.toDouble(), label: r['pickup_label']?.toString()),
                    icon: const Icon(Icons.navigation_outlined), label: const Text('Trace in Google Maps'),
                  ),
                if (status == 'in_progress')
                  OutlinedButton.icon(
                    onPressed: () => _openDirections(latitude: (r['destination_latitude'] as num?)?.toDouble(), longitude: (r['destination_longitude'] as num?)?.toDouble(), label: r['destination_label']?.toString()),
                    icon: const Icon(Icons.navigation_outlined), label: const Text('Trace in Google Maps'),
                  ),
                ...buttons,
              ])),
            ])));
          }).toList()),
        );
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

  Widget _loadFailure(String text, VoidCallback retry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 42, color: Color(0xFF176B57)),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(height: 1.45)),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
      ]),
    ),
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
  _Feature('Ride requests', 'View eligible trip offers', 'Eligible drivers receive ride requests in the app. Ride acceptance is checked before it takes effect.', Icons.notifications_active_rounded),
  _Feature('Active trip', 'Pickup, navigation and completion', 'Follow an authorised trip through pickup, in-progress and completed states.', Icons.route_rounded),
  _Feature('Availability', 'Go online or offline', 'Availability affects dispatch only after a verified driver account is authorised.', Icons.toggle_on_rounded),
  _Feature('Earnings', 'Trip totals and payout history', 'Private earnings and payout details are shown only to the authenticated account owner.', Icons.payments_rounded),
  _Feature('Safety and support', 'Help during a trip', 'Access safety guidance and support resources while protecting customer contact information.', Icons.health_and_safety_rounded),
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

class PartnerOnboardingPage extends StatefulWidget {
  const PartnerOnboardingPage({super.key, required this.role, required this.user, required this.existingRequest, required this.onSubmitted});
  final String role;
  final User user;
  final Map<String, dynamic>? existingRequest;
  final VoidCallback onSubmitted;
  @override
  State<PartnerOnboardingPage> createState() => _PartnerOnboardingPageState();
}

class _PartnerOnboardingPageState extends State<PartnerOnboardingPage> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final Map<String, TextEditingController> _extra = {};
  XFile? _photo;
  final Map<String, XFile?> _driverDocuments = <String, XFile?>{};
  final Map<String, String> _savedDriverDocumentPaths = <String, String>{};
  static const _driverDocumentLabels = <String>[
    'Driving licence',
    'Vehicle registration certificate (RC)',
    'Identity proof (Aadhaar or PAN)',
  ];
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _serviceAreas = <Map<String, dynamic>>[];
  bool _loadingServiceAreas = false;

  List<MapEntry<String, String>> get _fields => switch (widget.role) {
    'seller' => const [MapEntry('shop_name','Shop / business name *'), MapEntry('business_category','Business category *'), MapEntry('gstin','GSTIN (if applicable)')],
    'dark_store' => const [MapEntry('store_name','Dark store name *'), MapEntry('operating_hours','Operating hours *'), MapEntry('facility_details','Facility details (optional)')],
    'driver_partner' => const [MapEntry('vehicle_type','Vehicle type *'), MapEntry('vehicle_registration','Vehicle registration number *'), MapEntry('driving_licence_number','Driving licence number *'), MapEntry('service_area','Service PIN code *')],
    'delivery_partner' => const [MapEntry('vehicle_type','Vehicle type *'), MapEntry('vehicle_registration','Vehicle registration number *'), MapEntry('service_area','Service PIN code *')],
    _ => const [],
  };

  @override
  void initState() {
    super.initState();
    final r = widget.existingRequest ?? {};
    final rawDocuments = r['document_paths'];
    if (rawDocuments is List) {
      for (final raw in rawDocuments) {
        if (raw is Map) {
          final item = Map<String, dynamic>.from(raw);
          final label = item['label']?.toString().trim() ?? '';
          final path = item['path']?.toString().trim() ?? '';
          if (label.isNotEmpty && path.isNotEmpty) _savedDriverDocumentPaths[label] = path;
        } else if (raw is String && raw.trim().isNotEmpty) {
          _savedDriverDocumentPaths.putIfAbsent('Existing document', () => raw.trim());
        }
      }
    }
    final d = r['application_data'] is Map ? Map<String,dynamic>.from(r['application_data'] as Map) : <String,dynamic>{};
    _name.text = (r['display_name'] ?? widget.user.userMetadata?['full_name'] ?? widget.user.userMetadata?['name'] ?? '').toString();
    _phone.text = (r['phone'] ?? '').toString();
    _address.text = (d['address'] ?? '').toString();
    for (final f in _fields) { _extra[f.key] = TextEditingController(text: (d[f.key] ?? '').toString()); }
    if (widget.role == 'driver_partner' || widget.role == 'delivery_partner') {
      unawaited(_loadServiceAreas());
    }
  }
  @override
  void dispose() { _name.dispose(); _phone.dispose(); _address.dispose(); for (final c in _extra.values) { c.dispose(); } super.dispose(); }

  Future<void> _loadServiceAreas() async {
    if (mounted) setState(() => _loadingServiceAreas = true);
    try {
      final rows = await Supabase.instance.client.from('service_areas')
        .select('pincode,locality,district,state').eq('active', true).order('pincode');
      final areas = List<Map<String, dynamic>>.from(rows as List);
      if (!mounted) return;
      setState(() {
        _serviceAreas = areas;
        final selected = _extra['service_area']?.text.trim() ?? '';
        if (selected.isNotEmpty && !areas.any((row) => row['pincode']?.toString() == selected)) {
          _extra['service_area']?.clear();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load active service PIN codes. Please check your connection and retry.');
    } finally {
      if (mounted) setState(() => _loadingServiceAreas = false);
    }
  }

  Future<void> _choosePhoto() async {
    try {
      final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
      if (p != null && mounted) setState(() { _photo = p; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = 'Could not open photo gallery: $e'); }
  }

  Future<void> _chooseDriverDocument(String label) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.camera_alt_outlined),
          title: const Text('Take a photo'),
          onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
        ),
      ])),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 88, maxWidth: 2000);
      if (file != null && mounted) setState(() { _driverDocuments[label] = file; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not capture or select $label. Check camera/gallery permission and retry.');
    }
  }

  Future<void> _submit() async {
    if (widget.role == 'driver_partner') {
      final missingDocuments = _driverDocumentLabels.where((label) =>
        _driverDocuments[label] == null && (_savedDriverDocumentPaths[label]?.isNotEmpty ?? false) == false).toList();
      if (missingDocuments.isNotEmpty) {
        setState(() => _error = 'Upload all required driver documents: ${missingDocuments.join(', ')}.');
        return;
      }
    }
    if (widget.role == 'driver_partner' || widget.role == 'delivery_partner') {
      final pin = _extra['service_area']?.text.trim() ?? '';
      if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin) ||
          !_serviceAreas.any((area) => area['pincode']?.toString() == pin)) {
        setState(() => _error = 'Select an active six-digit service PIN code before submitting.');
        return;
      }
    }
    if (!_key.currentState!.validate()) return;
    final existing = widget.existingRequest;
    final oldPath = existing?['profile_photo_path']?.toString();
    if (_photo == null && (oldPath == null || oldPath.isEmpty)) { setState(() => _error = 'Please upload a profile photo.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      var photoPath = oldPath;
      if (_photo != null) {
        final ext0 = _photo!.name.contains('.') ? _photo!.name.split('.').last.toLowerCase() : 'jpg';
        final ext = const {'jpg','jpeg','png','webp'}.contains(ext0) ? ext0 : 'jpg';
        final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
        photoPath = '${widget.user.id}/${widget.role}/profile_${DateTime.now().toUtc().millisecondsSinceEpoch}.$ext';
        await client.storage.from('partner-onboarding').uploadBinary(photoPath, await _photo!.readAsBytes(), fileOptions: FileOptions(contentType: mime, upsert: false));
      }
      dynamic documentPathsPayload = existing?['document_paths'] ?? <dynamic>[];
      if (widget.role == 'driver_partner') {
        final uploadedDocuments = <Map<String, String>>[];
        for (final label in _driverDocumentLabels) {
          final selectedFile = _driverDocuments[label];
          var savedPath = _savedDriverDocumentPaths[label];
          if (selectedFile != null) {
            final ext0 = selectedFile.name.contains('.') ? selectedFile.name.split('.').last.toLowerCase() : 'jpg';
            final ext = const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext0) ? ext0 : 'jpg';
            final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
            final safeName = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+      if (existing != null && (existing['status'] == 'rejected' ||
          (existing['status'] == 'pending' && existing['needs_correction'] == true))) {
        await client.from('role_requests').update(payload).eq('id', existing['id']);
      } else {
        await client.from('role_requests').insert(payload);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding request submitted. Please wait for Admin approval.')));
      widget.onSubmitted();
    } catch (e) {
      debugPrint('Partner onboarding submission failed (${e.runtimeType}): $e');
      final details = e.toString().toLowerCase();
      if (mounted) setState(() => _error =
        details.contains('service pin')
          ? 'Select an active six-digit service PIN code before submitting.'
          : details.contains('duplicate key') || details.contains('unique constraint')
            ? 'An application already exists for this account. Refresh the app and check its review status.'
            : details.contains('row-level security') || details.contains('permission denied')
              ? 'Your account could not save this application. Sign out and sign in again, then retry.'
              : details.contains('storage') || details.contains('bucket') || details.contains('upload')
                ? 'A document could not be uploaded. Check your connection and retry the upload.'
                : 'Could not submit onboarding. Check every required field and document, then retry.');
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.role.replaceAll('_',' ')} onboarding'), automaticallyImplyLeading: false),
    body: SafeArea(child: Form(key: _key, child: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.verified_user_outlined, size: 42),
      const SizedBox(height: 10),
      Text('Complete your details', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('This application is only for ${widget.role.replaceAll('_',' ')} access. You may use the same Google account in other Alteo partner apps and submit separate applications there.', style: const TextStyle(height: 1.45)),
      if (widget.existingRequest?['needs_correction'] == true) ...[
        Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF2D8), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Admin requested a correction', style: TextStyle(fontWeight: FontWeight.w900)),
            Text((widget.existingRequest?['correction_reason'] ?? 'Please review and correct the application details.').toString()),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 18),
      TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name *', border: OutlineInputBorder()), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null),
      const SizedBox(height: 12),
      TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number *', border: OutlineInputBorder()), validator: (v) { final n = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length; return n < 7 || n > 15 ? 'Enter a valid phone number' : null; }),
      const SizedBox(height: 12),
      TextFormField(controller: _address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address *', border: OutlineInputBorder()), validator: (v) => (v == null || v.trim().length < 5) ? 'Enter your complete address' : null),
      const SizedBox(height: 12),
      for (final f in _fields) ...[
        if (f.key == 'service_area' &&
            (widget.role == 'driver_partner' || widget.role == 'delivery_partner')) ...[
          if (_loadingServiceAreas)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String>(
              value: _serviceAreas.any((area) => area['pincode']?.toString() == _extra[f.key]!.text.trim())
                  ? _extra[f.key]!.text.trim() : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: f.value, border: const OutlineInputBorder(),
                helperText: 'Choose an active PIN code. Admin controls which localities are covered.'),
              items: _serviceAreas.map((area) {
                final pin = area['pincode']?.toString() ?? '';
                final locality = area['locality']?.toString().trim() ?? '';
                final district = area['district']?.toString().trim() ?? '';
                final parts = <String>[pin, if (locality.isNotEmpty) locality, if (district.isNotEmpty) district];
                return DropdownMenuItem<String>(value: pin, child: Text(parts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: _saving || _serviceAreas.isEmpty ? null : (value) {
                if (value != null) setState(() { _extra[f.key]!.text = value; _error = null; });
              },
              validator: (value) => value != null &&
                  RegExp(r'^[1-9][0-9]{5}$').hasMatch(value) &&
                  _serviceAreas.any((area) => area['pincode']?.toString() == value)
                    ? null : (_serviceAreas.isEmpty ? 'No active PIN codes are configured. Contact Admin.' : 'Select an active six-digit PIN code.'),
            ),
          if (!_loadingServiceAreas && _serviceAreas.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Admin must add and activate a service PIN before you can apply.', style: TextStyle(color: Color(0xFFB3261E)))),
        ] else
          TextFormField(controller: _extra[f.key], decoration: InputDecoration(labelText: f.value, border: const OutlineInputBorder()),
            validator: (v) => f.value.endsWith('*') && (v == null || v.trim().isEmpty) ? 'This field is required' : null),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(onPressed: _saving ? null : _choosePhoto, icon: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_outline), label: Text(_photo == null ? (widget.existingRequest?['profile_photo_path'] == null ? 'Upload profile photo *' : 'Replace profile photo') : 'Profile photo selected')),
      if (widget.role == 'driver_partner') ...[
        const SizedBox(height: 20),
        const Text('Identity & vehicle documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('Upload clear, readable photos. These files are private and available to Admin reviewers only.',
          style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
        const SizedBox(height: 8),
        for (final label in _driverDocumentLabels)
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.verified_user_outlined, color: Color(0xFF2463D4)),
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                _driverDocuments[label]?.name ??
                  ((_savedDriverDocumentPaths[label]?.isNotEmpty ?? false) ? 'Document uploaded · tap to replace' : 'Required · upload a clear photo'),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Upload or replace $label',
                onPressed: _saving ? null : () => _chooseDriverDocument(label),
                icon: Icon(_driverDocuments[label] != null || (_savedDriverDocumentPaths[label]?.isNotEmpty ?? false)
                  ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                  color: _driverDocuments[label] != null || (_savedDriverDocumentPaths[label]?.isNotEmpty ?? false)
                    ? const Color(0xFF176B57) : const Color(0xFF2463D4)),
              ),
            ),
          ),
      ],
      if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
      const SizedBox(height: 18),
      FilledButton(onPressed: _saving ? null : _submit, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: _saving ? const CircularProgressIndicator() : const Text('Submit onboarding request')),
      const SizedBox(height: 10),
      const Text('Your details are stored securely for Admin review. Protected features stay locked until approval.', textAlign: TextAlign.center, style: TextStyle(height: 1.4)),
    ]))),
  );
}
), '');
            savedPath = '${widget.user.id}/${widget.role}/documents/${safeName}_${DateTime.now().toUtc().millisecondsSinceEpoch}.$ext';
            await client.storage.from('partner-onboarding').uploadBinary(
              savedPath,
              await selectedFile.readAsBytes(),
              fileOptions: FileOptions(contentType: mime, upsert: false),
            );
          }
          if (savedPath != null && savedPath.isNotEmpty) uploadedDocuments.add({'label': label, 'path': savedPath});
        }
        for (final entry in _savedDriverDocumentPaths.entries) {
          if (!_driverDocumentLabels.contains(entry.key)) uploadedDocuments.add({'label': entry.key, 'path': entry.value});
        }
        documentPathsPayload = uploadedDocuments;
      }
      final data = <String,dynamic>{'address': _address.text.trim()};
      for (final f in _fields) { final v = _extra[f.key]!.text.trim(); if (v.isNotEmpty) data[f.key] = v; }
      final payload = <String,dynamic>{
        'user_id': widget.user.id, 'requested_role': widget.role, 'status': 'pending',
        'email': widget.user.email, 'display_name': _name.text.trim(), 'phone': _phone.text.trim(),
        'profile_photo_path': photoPath, 'application_data': data,
        'document_paths': documentPathsPayload, 'rejection_reason': null,
        'needs_correction': false, 'correction_reason': null,
        'reviewed_at': null, 'reviewed_by': null, 'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (existing != null && (existing['status'] == 'rejected' ||
          (existing['status'] == 'pending' && existing['needs_correction'] == true))) {
        await client.from('role_requests').update(payload).eq('id', existing['id']);
      } else {
        await client.from('role_requests').insert(payload);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding request submitted. Please wait for Admin approval.')));
      widget.onSubmitted();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().toLowerCase().contains('service pin')
          ? 'Select an active six-digit service PIN code before submitting.'
          : 'Could not submit onboarding. Please check your details and connection, then retry.');
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.role.replaceAll('_',' ')} onboarding'), automaticallyImplyLeading: false),
    body: SafeArea(child: Form(key: _key, child: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.verified_user_outlined, size: 42),
      const SizedBox(height: 10),
      Text('Complete your details', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('This application is only for ${widget.role.replaceAll('_',' ')} access. You may use the same Google account in other Alteo partner apps and submit separate applications there.', style: const TextStyle(height: 1.45)),
      if (widget.existingRequest?['needs_correction'] == true) ...[
        Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF2D8), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Admin requested a correction', style: TextStyle(fontWeight: FontWeight.w900)),
            Text((widget.existingRequest?['correction_reason'] ?? 'Please review and correct the application details.').toString()),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 18),
      TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name *', border: OutlineInputBorder()), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null),
      const SizedBox(height: 12),
      TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number *', border: OutlineInputBorder()), validator: (v) { final n = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length; return n < 7 || n > 15 ? 'Enter a valid phone number' : null; }),
      const SizedBox(height: 12),
      TextFormField(controller: _address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address *', border: OutlineInputBorder()), validator: (v) => (v == null || v.trim().length < 5) ? 'Enter your complete address' : null),
      const SizedBox(height: 12),
      for (final f in _fields) ...[
        if (f.key == 'service_area' &&
            (widget.role == 'driver_partner' || widget.role == 'delivery_partner')) ...[
          if (_loadingServiceAreas)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String>(
              value: _serviceAreas.any((area) => area['pincode']?.toString() == _extra[f.key]!.text.trim())
                  ? _extra[f.key]!.text.trim() : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: f.value, border: const OutlineInputBorder(),
                helperText: 'Choose an active PIN code. Admin controls which localities are covered.'),
              items: _serviceAreas.map((area) {
                final pin = area['pincode']?.toString() ?? '';
                final locality = area['locality']?.toString().trim() ?? '';
                final district = area['district']?.toString().trim() ?? '';
                final parts = <String>[pin, if (locality.isNotEmpty) locality, if (district.isNotEmpty) district];
                return DropdownMenuItem<String>(value: pin, child: Text(parts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: _saving || _serviceAreas.isEmpty ? null : (value) {
                if (value != null) setState(() { _extra[f.key]!.text = value; _error = null; });
              },
              validator: (value) => value != null &&
                  RegExp(r'^[1-9][0-9]{5}$').hasMatch(value) &&
                  _serviceAreas.any((area) => area['pincode']?.toString() == value)
                    ? null : (_serviceAreas.isEmpty ? 'No active PIN codes are configured. Contact Admin.' : 'Select an active six-digit PIN code.'),
            ),
          if (!_loadingServiceAreas && _serviceAreas.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Admin must add and activate a service PIN before you can apply.', style: TextStyle(color: Color(0xFFB3261E)))),
        ] else
          TextFormField(controller: _extra[f.key], decoration: InputDecoration(labelText: f.value, border: const OutlineInputBorder()),
            validator: (v) => f.value.endsWith('*') && (v == null || v.trim().isEmpty) ? 'This field is required' : null),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(onPressed: _saving ? null : _choosePhoto, icon: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_outline), label: Text(_photo == null ? (widget.existingRequest?['profile_photo_path'] == null ? 'Upload profile photo *' : 'Replace profile photo') : 'Profile photo selected')),
      if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
      const SizedBox(height: 18),
      FilledButton(onPressed: _saving ? null : _submit, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: _saving ? const CircularProgressIndicator() : const Text('Submit onboarding request')),
      const SizedBox(height: 10),
      const Text('Your details are stored securely for Admin review. Protected features stay locked until approval.', textAlign: TextAlign.center, style: TextStyle(height: 1.4)),
    ]))),
  );
}
