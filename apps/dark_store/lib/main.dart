import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const appName = 'Alteo Dark Store';
const requiredRole = 'dark_store';
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://nkerkoptbrcadlpxffkn.supabase.co');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_lM6ttzw8KMPH2BNXgMAJVA_3y1h51YD');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var backendReady = false;
  try {
    if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
      backendReady = true;
    }
  } catch (_) {
    // Public feature exploration must not depend on sign-in availability.
  }
  runApp(AlteoDarkStoreApp(backendReady: backendReady));
}

class AlteoDarkStoreApp extends StatelessWidget {
  const AlteoDarkStoreApp({super.key, required this.backendReady});
  final bool backendReady;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F6),
      useMaterial3: true,
    ),
    home: DarkStoreExplorePage(backendReady: backendReady),
  );
}

class _Feature {
  const _Feature(this.title, this.subtitle, this.description, this.icon);
  final String title, subtitle, description;
  final IconData icon;
}

const _features = <_Feature>[
  _Feature('Stock overview', 'Inventory and low-stock visibility', 'Review stock by SKU and location, identify low-stock items, and keep available quantities consistent with seller and customer catalogues.', Icons.inventory_2_rounded),
  _Feature('Picking queue', 'Items to pick for accepted orders', 'Orders routed to this dark store appear in the picking queue after the shared backend and role permissions are configured.', Icons.checklist_rounded),
  _Feature('Packing station', 'Verify items before dispatch', 'Confirm quantities and packing status before an order is marked ready for pickup.', Icons.inventory_rounded),
  _Feature('Dispatch handover', 'Coordinate with delivery partners', 'Ready orders can be handed to the assigned delivery partner with a server-validated status transition.', Icons.local_shipping_rounded),
  _Feature('Stock adjustments', 'Receive and reconcile stock', 'Authorised staff can record stock receipts, adjustments and an audit trail without exposing inventory controls publicly.', Icons.fact_check_rounded),
];

class DarkStoreExplorePage extends StatelessWidget {
  const DarkStoreExplorePage({super.key, required this.backendReady});
  final bool backendReady;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alteo Dark Store')),
    body: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF49A27D)]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('FULFILMENT OPERATIONS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          SizedBox(height: 10),
          Text('Stock in. Orders out.', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text('Explore stock management, picking, packing and dispatch. Sign-in is only needed to change real operational records.', style: TextStyle(color: Colors.white, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 22),
      const Text('Explore features', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      const Text('No login is needed to explore these screens.', style: TextStyle(color: Color(0xFF68736D))),
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
            onTap: () => showModalBottomSheet<void>(
              context: context, showDragHandle: true,
              builder: (context) => SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(feature.icon, size: 38, color: const Color(0xFF176B57)),
                  const SizedBox(height: 12),
                  Text(feature.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(feature.description, style: const TextStyle(height: 1.5)),
                  const SizedBox(height: 12),
                  const Text('Real stock and order records are protected and become available to authorised staff when the shared backend workflow is deployed.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Continue exploring'))),
                ]),
              )),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        backendReady
          ? 'Backend connection initialised. Inventory and fulfilment records still require the shared schema and role policies.'
          : 'Public exploration is available. Live operations are temporarily unavailable until backend configuration is restored.',
        style: const TextStyle(color: Color(0xFF68736D), height: 1.45),
      ),
    ]),
  );
}
