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
  runApp(AlteoDarkStoreApp(client: client, configError: error));
}
class AlteoDarkStoreApp extends StatelessWidget {
  const AlteoDarkStoreApp({super.key, required this.client, required this.configError});
  final SupabaseClient? client;
  final String? configError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Alteo Dark Store', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF176B57)),
      scaffoldBackgroundColor:const Color(0xFFF7F8F6)),
    home:client==null?_ConfigScreen(message:configError??'Configuration needed.'):_AuthGate(client:client!),
  );
}
class _ConfigScreen extends StatelessWidget {
  const _ConfigScreen({required this.message});
  final String message;
  @override
  Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.warehouse_outlined,size:60,color:Color(0xFF176B57)),
    const SizedBox(height:12),Text('Alteo Dark Store',style:Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height:12),Text(message,textAlign:TextAlign.center),
  ])))));
}
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.client});
  final SupabaseClient client;
  @override
  State<_AuthGate> createState()=>_AuthGateState();
}
class _AuthGateState extends State<_AuthGate>{
  User? _user;
  late final StreamSubscription<AuthState> _subscription;
  @override
  void initState(){super.initState();_user=widget.client.auth.currentUser;_subscription=widget.client.auth.onAuthStateChange.listen((e){if(mounted)setState(()=>_user=e.session?.user);});}
  @override
  void dispose(){_subscription.cancel();super.dispose();}
  @override
  Widget build(BuildContext context)=>_user==null?_LoginScreen(client:widget.client):_StoreRouter(client:widget.client,user:_user!);
}
class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.client});
  final SupabaseClient client;
  @override
  State<_LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<_LoginScreen>{
  final _phone=TextEditingController(),_otp=TextEditingController();
  bool _sent=false,_busy=false;
  String? _error;
  @override
  void dispose(){_phone.dispose();_otp.dispose();super.dispose();}
  Future<void> _submit() async {
    final phone=_phone.text.trim();
    if(!_sent&&!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)){setState(()=>_error='Enter phone with country code, e.g. +919876543210.');return;}
    if(_sent&&!RegExp(r'^\d{6}$').hasMatch(_otp.text.trim())){setState(()=>_error='Enter the six-digit code.');return;}
    setState(()=>_busy=true);setState(()=>_error=null);
    try{
      if(!_sent){await widget.client.auth.signInWithOtp(phone:phone);if(mounted)setState(()=>_sent=true);}
      else{await widget.client.auth.verifyOTP(phone:phone,token:_otp.text.trim(),type:OtpType.sms);}
    }on AuthException catch(e){if(mounted)setState(()=>_error=e.message);}
    catch(_){if(mounted)setState(()=>_error='Sign-in failed. Check SMS provider settings.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(
    constraints:const BoxConstraints(maxWidth:420),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Icon(Icons.warehouse_outlined,size:60,color:Color(0xFF176B57)),
      const SizedBox(height:12),Text('Dark-store operator sign-in',textAlign:TextAlign.center,style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),
      const SizedBox(height:8),const Text('Use your approved operator mobile number.',textAlign:TextAlign.center),
      const SizedBox(height:24),TextField(controller:_phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Mobile number',hintText:'+919876543210')),
      if(_sent)...[const SizedBox(height:12),TextField(controller:_otp,keyboardType:TextInputType.number,maxLength:6,decoration:const InputDecoration(labelText:'SMS code'))],
      if(_error!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      const SizedBox(height:16),FilledButton(onPressed:_busy?null:_submit,child:_busy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):Text(_sent?'Verify and continue':'Send OTP')),
      if(_sent)TextButton(onPressed:_busy?null:()=>setState(()=>_sent=false),child:const Text('Change mobile number')),
    ])),
  )))));
}
class _StoreRouter extends StatefulWidget {
  const _StoreRouter({required this.client,required this.user});
  final SupabaseClient client;
  final User user;
  @override
  State<_StoreRouter> createState()=>_StoreRouterState();
}
class _StoreRouterState extends State<_StoreRouter>{
  late Future<Map<String,dynamic>?> _store;
  late Future<bool> _role;
  @override
  void initState(){super.initState();_refresh();}
  void _refresh(){
    _role=widget.client.from('user_roles').select('role').eq('user_id',widget.user.id).eq('role','dark_store').limit(1).then((rows)=>rows.isNotEmpty);
    _store=widget.client.from('dark_stores').select('id,name,locality,status,owner_user_id').eq('owner_user_id',widget.user.id).order('created_at',ascending:false).limit(1).maybeSingle();
  }
  @override
  Widget build(BuildContext context)=>FutureBuilder<List<Object?>>(
    future:Future.wait<Object?>([_role,_store]),builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const Scaffold(body:Center(child:CircularProgressIndicator()));
      if(snapshot.hasError||snapshot.data?[0]!=true)return Scaffold(appBar:AppBar(title:const Text('Alteo Dark Store')),body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.lock_outline,size:48),const SizedBox(height:12),const Text('Dark-store access has not been granted.',textAlign:TextAlign.center),
        const SizedBox(height:12),OutlinedButton(onPressed:()async=>widget.client.auth.signOut(),child:const Text('Sign out')),
      ]))));
      final store=snapshot.data?[1] as Map<String,dynamic>?;
      if(store==null)return Scaffold(appBar:AppBar(title:const Text('Alteo Dark Store')),body:const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('No store is assigned to this operator. Contact Alteo admin.'))));
      if(store['status']!='active')return Scaffold(appBar:AppBar(title:const Text('Store approval')),body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.hourglass_top,size:48),const SizedBox(height:12),Text(store['name'].toString(),style:Theme.of(context).textTheme.titleLarge),
        const SizedBox(height:8),Text('Status: '+store['status'].toString()),const SizedBox(height:8),
        const Text('Your stock tools unlock after an administrator activates this store.',textAlign:TextAlign.center),
        TextButton(onPressed:()=>setState(_refresh),child:const Text('Refresh status')),
      ]))));
      return _InventoryHome(client:widget.client,user:widget.user,store:store);
    });
}

class _InventoryRow {
  const _InventoryRow({required this.inventory,required this.product});
  final Map<String,dynamic> inventory;
  final Map<String,dynamic> product;
}
class _InventoryHome extends StatefulWidget {
  const _InventoryHome({required this.client,required this.user,required this.store});
  final SupabaseClient client;
  final User user;
  final Map<String,dynamic> store;
  @override
  State<_InventoryHome> createState()=>_InventoryHomeState();
}
class _InventoryHomeState extends State<_InventoryHome>{
  late Future<List<_InventoryRow>> _inventory;
  late Future<List<Map<String,dynamic>>> _catalogue;
  int _tab=0;
  String get _storeId=>widget.store['id'].toString();
  @override
  void initState(){super.initState();_refresh();}
  Future<List<_InventoryRow>> _loadInventory() async {
    final rows=await widget.client.from('dark_store_inventory').select('id,product_id,stock_on_hand,reserved_quantity,updated_at')
      .eq('store_id',_storeId).order('updated_at',ascending:false).limit(200);
    final result=< _InventoryRow >[];
    for(final raw in rows){
      final inventory=Map<String,dynamic>.from(raw);
      final p=await widget.client.from('seller_products').select('id,name,kind,price_minor,status')
        .eq('id',inventory['product_id']).maybeSingle();
      if(p!=null)result.add(_InventoryRow(inventory:inventory,product:Map<String,dynamic>.from(p)));
    }
    return result;
  }
  void _refresh(){
    _inventory=_loadInventory();
    _catalogue=widget.client.from('seller_products').select('id,name,kind,price_minor,status')
      .eq('status','active').order('name').limit(200).then((rows)=>rows.map((r)=>Map<String,dynamic>.from(r)).toList());
  }
  Future<void> _setStock(String productId,int stock) async {
    try{
      await widget.client.rpc('dark_store_set_inventory',params:{'p_store_id':_storeId,'p_product_id':productId,'p_stock_on_hand':stock});
      if(mounted){setState(_refresh);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Inventory updated.')));}
    }on PostgrestException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message)));}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not update stock.')));}
  }
  Future<void> _addItem() async {
    final products=await _catalogue;
    if(!mounted)return;
    if(products.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No active catalogue products are available.')));return;}
    String productId=products.first['id'].toString();
    final qty=TextEditingController(text:'0');
    final result=await showDialog<Map<String,dynamic>>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setDialog)=>AlertDialog(
      title:const Text('Add or update stock'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(value:productId,decoration:const InputDecoration(labelText:'Catalogue item'),
          items:products.map((p)=>DropdownMenuItem(value:p['id'].toString(),child:Text(p['name'].toString(),maxLines:1,overflow:TextOverflow.ellipsis))).toList(),
          onChanged:(v){if(v!=null)setDialog(()=>productId=v);}),
        const SizedBox(height:12),TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Stock on hand',helperText:'Enter total physical stock; it cannot go below reserved quantity.')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,{'product':productId,'quantity':int.tryParse(qty.text.trim())}),child:const Text('Save stock'))],
    )));
    qty.dispose();
    if(result==null)return;
    final n=result['quantity'] as int?;
    if(n==null||n<0){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a non-negative stock quantity.')));return;}
    await _setStock(result['product'].toString(),n);
  }
  Future<void> _editStock(_InventoryRow row) async {
    final qty=TextEditingController(text:row.inventory['stock_on_hand'].toString());
    final result=await showDialog<int>(context:context,builder:(context)=>AlertDialog(
      title:Text('Stock: '+row.product['name'].toString()),
      content:TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Stock on hand')),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,int.tryParse(qty.text.trim())),child:const Text('Save'))],
    ));
    qty.dispose();
    if(result!=null&&result>=0)await _setStock(row.product['id'].toString(),result);
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.store['name'].toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
      actions:[IconButton(tooltip:'Refresh',onPressed:()=>setState(_refresh),icon:const Icon(Icons.refresh)),IconButton(tooltip:'Sign out',onPressed:()async=>widget.client.auth.signOut(),icon:const Icon(Icons.logout))]),
    body:IndexedStack(index:_tab,children:[
      RefreshIndicator(onRefresh:()async{setState(_refresh);await _inventory;},child:ListView(padding:const EdgeInsets.all(16),children:[
        Row(children:[Expanded(child:Text('Stock inventory',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),
          ),FilledButton.tonalIcon(onPressed:_addItem,icon:const Icon(Icons.add),label:const Text('Add item'))]),
        const SizedBox(height:6),const Text('Stock updates are audited. Products come from the shared Alteo catalogue; this screen controls this store’s on-hand stock.'),
        FutureBuilder<List<_InventoryRow>>(future:_inventory,builder:(context,snapshot){
          if(snapshot.connectionState!=ConnectionState.done)return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));
          if(snapshot.hasError)return const Text('Inventory could not be loaded. Refresh and retry.');
          final rows=snapshot.data??[];
          if(rows.isEmpty)return const _StoreNotice(title:'No stock recorded',detail:'Add an active catalogue product and set its quantity.');
          return Column(children:rows.map((row){
            final stock=(row.inventory['stock_on_hand'] as num?)?.toInt()??0;
            final reserved=(row.inventory['reserved_quantity'] as num?)?.toInt()??0;
            final price=((row.product['price_minor'] as num?)?.toInt()??0)/100;
            return Card(child:ListTile(
              leading:const CircleAvatar(child:Icon(Icons.inventory_2_outlined)),
              title:Text(row.product['name'].toString()),
              subtitle:Text('Stock '+stock.toString()+' • Reserved '+reserved.toString()+' • ₹'+price.toStringAsFixed(2)),
              trailing:IconButton(tooltip:'Edit stock',onPressed:()=>_editStock(row),icon:const Icon(Icons.edit_outlined)),
            ));
          }).toList());
        }),
      ])),
      ListView(padding:const EdgeInsets.all(16),children:[
        Text('Store details',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),
        Card(child:Column(children:[
          ListTile(leading:const Icon(Icons.warehouse_outlined),title:Text(widget.store['name'].toString()),subtitle:const Text('Active dark store')),
          ListTile(leading:const Icon(Icons.location_on_outlined),title:Text(widget.store['locality']?.toString()??'Locality not set')),
          ListTile(leading:const Icon(Icons.inventory_2_outlined),title:const Text('Stock controlled by this store')),
        ])),
        const _StoreNotice(title:'Order fulfilment integration',detail:'Customer order reservation and dark-store-specific fulfilment still require the dedicated dark-store checkout path. This app currently manages local stock only; do not treat this as a live dispatch console.'),
      ]),
    ]),
    bottomNavigationBar:NavigationBar(selectedIndex:_tab,onDestinationSelected:(v)=>setState(()=>_tab=v),destinations:const[
      NavigationDestination(icon:Icon(Icons.inventory_2_outlined),selectedIcon:Icon(Icons.inventory_2),label:'Inventory'),
      NavigationDestination(icon:Icon(Icons.warehouse_outlined),selectedIcon:Icon(Icons.warehouse),label:'Store'),
    ]),
  );
}

class _StoreNotice extends StatelessWidget {
  const _StoreNotice({required this.title,required this.detail});
  final String title,detail;
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(18),child:Column(children:[
    const Icon(Icons.info_outline,size:38),const SizedBox(height:8),
    Text(title,style:const TextStyle(fontWeight:FontWeight.w800),textAlign:TextAlign.center),
    const SizedBox(height:6),Text(detail,textAlign:TextAlign.center),
  ]));
}
