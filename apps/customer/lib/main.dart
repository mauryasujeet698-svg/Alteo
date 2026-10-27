import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alteo_notifications/alteo_notifications.dart';
import 'src/config/app_config.dart';
import 'src/features/home/customer_home_page.dart';
import 'src/features/account/customer_account_page.dart';
import 'src/features/services/service_browse_page.dart';
import 'src/services/mapbox_service.dart';
import 'src/services/customer_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadCustomerPreferences();
  final config = AppConfig.fromEnvironment();
  String? backendNotice;
  try {
    if (config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) {
      backendNotice = 'Live catalogue and sign-in are unavailable until the backend configuration is restored.';
    } else {
      await Supabase.initialize(url: config.supabaseUrl, publishableKey: config.supabaseAnonKey);
    }
  } catch (_) {
    // Do not block public browsing when Supabase is temporarily unavailable.
    backendNotice = 'Live catalogue and sign-in are temporarily unavailable. You can still explore Alteo services.';
  }
  MapboxService.configure(config.mapboxPublicToken);
  if (backendNotice == null) {
    unawaited(AlteoPushNotifications.instance.initialize(
      client: Supabase.instance.client,
      appId: 'customer',
    ));
  }
  runApp(AlteoCustomerApp(backendNotice: backendNotice));
}

class AlteoCustomerApp extends StatelessWidget {
  const AlteoCustomerApp({super.key, this.backendNotice, this.enableRealtimeBanners = true, this.enableBackendQueries = true});
  final String? backendNotice;
  final bool enableRealtimeBanners;
  final bool enableBackendQueries;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: alteoThemeMode,
    builder: (context, mode, _) => MaterialApp(
      title: 'Alteo',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57), brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F8F6), surfaceTintColor: Colors.transparent),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF43B58A), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: CustomerAppShell(backendNotice: backendNotice, enableRealtimeBanners: enableRealtimeBanners, enableBackendQueries: enableBackendQueries),
    ),
  );
}

class CustomerAppShell extends StatefulWidget {
  const CustomerAppShell({super.key, this.backendNotice, this.enableRealtimeBanners = true, this.enableBackendQueries = true});
  final String? backendNotice;
  final bool enableRealtimeBanners;
  final bool enableBackendQueries;
  @override
  State<CustomerAppShell> createState() => _CustomerAppShellState();
}

class _CustomerAppShellState extends State<CustomerAppShell> {
  int selected = 0;

  List<Widget> get pages {
    if (widget.backendNotice != null) {
      return [
        PublicExploreFallback(notice: widget.backendNotice!),
        const PublicServiceFallback(title: 'Food', detail: 'Food discovery will connect when the backend is available.'),
        const PublicServiceFallback(title: 'Ride', detail: 'Ride booking will connect when the backend is available.'),
        const CustomerAccountPage(),
      ];
    }
    return [
      CustomerHomePage(enableRealtimeBanners: widget.enableRealtimeBanners, enableBackendQueries: widget.enableBackendQueries),
      ServiceBrowsePage(service: 'Food', enableBackendQueries: widget.enableBackendQueries),
      ServiceBrowsePage(service: 'Rides', enableBackendQueries: widget.enableBackendQueries),
      CustomerAccountPage(),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: selected, children: pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (i) => setState(() => selected = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant_rounded), label: 'Food'),
        NavigationDestination(icon: Icon(Icons.directions_car_outlined), selectedIcon: Icon(Icons.directions_car_filled_rounded), label: 'Ride'),
        NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
      ],
    ),
  );
}

class PublicServiceFallback extends StatelessWidget {
  const PublicServiceFallback({super.key, required this.title, required this.detail});
  final String title, detail;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(detail, textAlign: TextAlign.center))),
  );
}

class PublicExploreFallback extends StatelessWidget {
  const PublicExploreFallback({super.key, required this.notice});
  final String notice;
  static const services = <(String, IconData, String)>[
    ('Food', Icons.restaurant_rounded, 'Browse restaurants, menus and meals.'),
    ('Quick commerce', Icons.shopping_basket_rounded, 'Explore groceries and everyday essentials.'),
    ('Shopping', Icons.shopping_bag_rounded, 'Explore products from marketplace sellers.'),
    ('Rides', Icons.directions_car_rounded, 'Explore bike and car ride services.'),
    ('Parcels', Icons.local_shipping_rounded, 'Explore local pickup and delivery services.'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alteo')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF49A27D)]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('EVERYDAY SERVICES, TOGETHER', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          SizedBox(height: 10),
          Text('Explore Alteo', style: TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text('Browse services without creating an account. Sign-in is only needed for personal actions such as checkout.', style: TextStyle(color: Colors.white, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 18),
      Text(notice, style: const TextStyle(color: Color(0xFF68736D), height: 1.45)),
      const SizedBox(height: 16),
      for (final service in services)
        Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: const BorderSide(color: Color(0xFFE5EAE5))),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFFE3F2E9), child: Icon(service.$2, color: const Color(0xFF176B57))),
            title: Text(service.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(service.$3),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ServiceBrowsePage(service: service.$1 == 'Quick commerce' ? 'Quick' : service.$1 == 'Shopping' ? 'Shop' : service.$1 == 'Parcels' ? 'Parcel' : service.$1))),
          ),
        ),
    ]),
  );
}
