import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'src/config/app_config.dart';
import 'src/features/home/customer_home_page.dart';
import 'src/features/orders/customer_orders_page.dart';
import 'src/features/account/customer_account_page.dart';
import 'src/services/mapbox_service.dart';

Future<void> main() async {
 WidgetsFlutterBinding.ensureInitialized();
 final config=AppConfig.fromEnvironment();
 String? startupError;
 try {
  if(config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) {
   startupError='Supabase URL or public key is missing. Add SUPABASE_URL and SUPABASE_ANON_KEY to the app build configuration.';
  } else {
   await Supabase.initialize(url:config.supabaseUrl,publishableKey:config.supabaseAnonKey);
  }
 } catch(e) { startupError='Supabase could not be initialized. Verify the project URL and publishable key, internet access, and Supabase project status. Details: $e'; }
 MapboxService.configure(config.mapboxPublicToken);
 runApp(AlteoCustomerApp(startupError:startupError));
}
class AlteoCustomerApp extends StatelessWidget {
 const AlteoCustomerApp({super.key,this.startupError});
 final String? startupError;
 @override Widget build(BuildContext context)=>MaterialApp(
  title:'Alteo',debugShowCheckedModeBanner:false,
  theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF176B57),brightness:Brightness.light),scaffoldBackgroundColor:const Color(0xFFF7F8F6),useMaterial3:true,appBarTheme:const AppBarTheme(backgroundColor:Color(0xFFF7F8F6),surfaceTintColor:Colors.transparent)),
  home:startupError==null?const CustomerAppShell():_StartupErrorPage(message:startupError!),
 );
}
class CustomerAppShell extends StatefulWidget { const CustomerAppShell({super.key}); @override State<CustomerAppShell> createState()=>_CustomerAppShellState(); }
class _CustomerAppShellState extends State<CustomerAppShell> {
 int selected=0;
 final pages=const [CustomerHomePage(),CustomerOrdersPage(),CustomerAccountPage()];
 @override Widget build(BuildContext context)=>Scaffold(
  body:IndexedStack(index:selected,children:pages),
  bottomNavigationBar:NavigationBar(selectedIndex:selected,onDestinationSelected:(i)=>setState(()=>selected=i),destinations:const [
   NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home_rounded),label:'Home'),
   NavigationDestination(icon:Icon(Icons.receipt_long_outlined),selectedIcon:Icon(Icons.receipt_long_rounded),label:'Orders'),
   NavigationDestination(icon:Icon(Icons.person_outline_rounded),selectedIcon:Icon(Icons.person_rounded),label:'Account'),
  ]),
 );
}
class _StartupErrorPage extends StatelessWidget {
 const _StartupErrorPage({required this.message}); final String message;
 @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
  const Icon(Icons.cloud_off_rounded,size:58,color:Color(0xFF176B57)),const SizedBox(height:18),const Text('Alteo needs a connection',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900),textAlign:TextAlign.center),const SizedBox(height:12),Text(message,textAlign:TextAlign.center,style:const TextStyle(height:1.5,color:Color(0xFF68736D))),const SizedBox(height:20),const Text('Check the app configuration and reopen Alteo.',textAlign:TextAlign.center)
 ])))));
}