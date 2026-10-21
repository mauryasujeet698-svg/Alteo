import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/config/app_config.dart';
import 'src/services/mapbox_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

  if (config.supabaseUrl.isNotEmpty && config.supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: config.supabaseUrl, anonKey: config.supabaseAnonKey);
  }
  MapboxService.configure(config.mapboxPublicToken);
  runApp(const AlteoCustomerApp());
}

class AlteoCustomerApp extends StatelessWidget {
  const AlteoCustomerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Alteo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)),
          useMaterial3: true,
        ),
        home: const CustomerStartPage(),
      );
}

class CustomerStartPage extends StatelessWidget {
  const CustomerStartPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Alteo')),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.explore_outlined, size: 64),
                  SizedBox(height: 16),
                  Text('Everything you need, in one place', textAlign: TextAlign.center),
                  SizedBox(height: 8),
                  Text(
                    'Customer app foundation. Configure the environment and verify backend policies before enabling live services.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
