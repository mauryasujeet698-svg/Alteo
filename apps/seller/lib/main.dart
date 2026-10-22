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
  runApp(AlteoSellerApp(client: client, configError: error));
}
class AlteoSellerApp extends StatelessWidget {
  const AlteoSellerApp({super.key, required this.client, required this.configError});
  final SupabaseClient? client;
  final String? configError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Alteo Seller', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F6), inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true)),
    home: client == null ? _ConfigScreen(message: configError ?? 'Configuration needed.') : _AuthGate(client: client!),
  );
}
class _ConfigScreen extends StatelessWidget {
  const _ConfigScreen({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.storefront_outlined, size: 60, color: Color(0xFF176B57)),
      const SizedBox(height: 12), Text('Alteo Seller', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12), Text(message, textAlign: TextAlign.center),
    ]),
  ))));
}
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.client});
  final SupabaseClient client;
  @override
  State<_AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<_AuthGate> {
  User? _user;
  late final StreamSubscription<AuthState> _subscription;
  @override
  void initState() {
    super.initState();
    _user = widget.client.auth.currentUser;
    _subscription = widget.client.auth.onAuthStateChange.listen((e) { if (mounted) setState(() => _user = e.session?.user); });
  }
  @override
  void dispose() { _subscription.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => _user == null ? _LoginScreen(client: widget.client) : _SellerRouter(client: widget.client, user: _user!);
}
class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.client});
  final SupabaseClient client;
  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<_LoginScreen> {
  final _phone = TextEditingController(), _otp = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;
  @override
  void dispose() { _phone.dispose(); _otp.dispose(); super.dispose(); }
  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (!_sent && !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) { setState(() => _error = 'Enter phone with country code, e.g. +919876543210.'); return; }
    if (_sent && !RegExp(r'^\d{6}$').hasMatch(_otp.text.trim())) { setState(() => _error = 'Enter the six-digit code.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      if (!_sent) { await widget.client.auth.signInWithOtp(phone: phone); if (mounted) setState(() => _sent = true); }
      else { await widget.client.auth.verifyOTP(phone: phone, token: _otp.text.trim(), type: OtpType.sms); }
    } on AuthException catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Sign-in failed. Check SMS provider settings.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.storefront_outlined, size: 60, color: Color(0xFF176B57)),
        const SizedBox(height: 12), Text('Seller sign-in', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8), const Text('Apply to sell on Alteo or manage your approved shop.', textAlign: TextAlign.center),
        const SizedBox(height: 24), TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+919876543210')),
        if (_sent) ...[
          const SizedBox(height: 12), TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'SMS code')),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16), FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 20,height:20,child:CircularProgressIndicator(strokeWidth:2)) : Text(_sent ? 'Verify and continue' : 'Send OTP')),
        if (_sent) TextButton(onPressed: _busy ? null : () => setState(() { _sent=false; _otp.clear(); _error=null; }), child: const Text('Change phone number')),
      ],
    )),
  ))));
}

class _SellerRouter extends StatefulWidget {
  const _SellerRouter({required this.client, required this.user});
  final SupabaseClient client;
  final User user;
  @override
  State<_SellerRouter> createState() => _SellerRouterState();
}
class _SellerRouterState extends State<_SellerRouter> {
  late Future<Map<String, dynamic>?> _seller;
  @override
  void initState() { super.initState(); _refresh(); }
  void _refresh() { _seller = widget.client.from('sellers').select('id,owner_id,display_name,phone,contact_email,status,created_at')
    .eq('owner_id', widget.user.id).order('created_at', ascending: false).limit(1).maybeSingle(); }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(future: _seller, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (snapshot.hasError) return Scaffold(appBar: AppBar(title: const Text('Alteo Seller')), body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Could not load seller profile.'), TextButton(onPressed: () => setState(_refresh), child: const Text('Retry')),
    ])));
    final seller = snapshot.data;
    if (seller == null) return _SellerApplication(client: widget.client, onSubmitted: () { if (mounted) setState(_refresh); });
    if (seller['status'] != 'approved') return _PendingScreen(client: widget.client, seller: seller, onRefresh: () => setState(_refresh));
    return _SellerHome(client: widget.client, seller: seller, user: widget.user);
  });
}

class _SellerApplication extends StatefulWidget {
  const _SellerApplication({required this.client, required this.onSubmitted});
  final SupabaseClient client;
  final VoidCallback onSubmitted;
  @override
  State<_SellerApplication> createState() => _SellerApplicationState();
}
class _SellerApplicationState extends State<_SellerApplication> {
  final _name = TextEditingController(), _phone = TextEditingController(), _email = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _name.dispose(); _phone.dispose(); _email.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (_name.text.trim().length < 2 || _phone.text.trim().length < 8) { setState(() => _error = 'Enter a shop name and valid contact phone.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.client.from('sellers').insert({
        'display_name': _name.text.trim(), 'phone': _phone.text.trim(),
        if (_email.text.trim().isNotEmpty) 'contact_email': _email.text.trim(),
      });
      widget.onSubmitted();
    } on PostgrestException catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Application could not be submitted.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Seller application')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.storefront_outlined, size: 48, color: Color(0xFF176B57)),
      Text('Start selling on Alteo', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8), const Text('Submit your shop details. Alteo will review and approve your application before your products become visible.'),
      const SizedBox(height: 18), TextField(controller: _name, decoration: const InputDecoration(labelText: 'Shop / business name')),
      const SizedBox(height: 12), TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact number')),
      const SizedBox(height: 12), TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 18), FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Submitting…' : 'Submit application')),
      const SizedBox(height: 18), const Text('For operational onboarding, keep your business and bank documents ready for Alteo administrator review.', style: TextStyle(color: Colors.black54)),
    ])));
}

class _PendingScreen extends StatelessWidget {
  const _PendingScreen({required this.client, required this.seller, required this.onRefresh});
  final SupabaseClient client;
  final Map<String, dynamic> seller;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Seller approval')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(seller['status'] == 'approved' ? Icons.check_circle : Icons.hourglass_top, size: 54, color: const Color(0xFF176B57)),
      const SizedBox(height: 12), Text(seller['display_name']?.toString() ?? 'Your shop', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8), Text('Application status: ' + seller['status'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8), const Text('You can manage products and orders after an administrator approves the shop.', textAlign: TextAlign.center),
      const SizedBox(height: 18), OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh), label: const Text('Check approval')),
      const SizedBox(height: 8), TextButton(onPressed: () async => client.auth.signOut(), child: const Text('Sign out')),
    ]))));
}

class _SellerHome extends StatefulWidget {
  const _SellerHome({required this.client, required this.seller, required this.user});
  final SupabaseClient client;
  final Map<String, dynamic> seller;
  final User user;
  @override
  State<_SellerHome> createState() => _SellerHomeState();
}
class _SellerHomeState extends State<_SellerHome> {
  int _tab = 0;
  late Future<List<Map<String, dynamic>>> _products;
  late Future<List<Map<String, dynamic>>> _orders;
  String get _sellerId => widget.seller['id'].toString();
  @override
  void initState() { super.initState(); _refresh(); }
  void _refresh() {
    _products = widget.client.from('seller_products').select('id,name,kind,description,price_minor,currency,status,created_at,seller_inventory(stock_on_hand,reserved_quantity)')
      .eq('seller_id', _sellerId).order('created_at', ascending: false).limit(100)
      .then((rows) => rows.map((r) {
        final product = Map<String, dynamic>.from(r);
        final inventory = product.remove('seller_inventory');
        if (inventory is List && inventory.isNotEmpty && inventory.first is Map) {
          product['stock_on_hand'] = inventory.first['stock_on_hand'];
          product['reserved_quantity'] = inventory.first['reserved_quantity'];
        } else {
          product['stock_on_hand'] = 0;
          product['reserved_quantity'] = 0;
        }
        return product;
      }).toList());
    _orders = widget.client.from('orders').select('id,status,payment_status,total_minor,currency,created_at')
      .eq('seller_id', _sellerId).order('created_at', ascending: false).limit(100)
      .then((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }
  Future<void> _editProduct({Map<String, dynamic>? product}) async {
    final name = TextEditingController(text: product?['name']?.toString() ?? '');
    final description = TextEditingController(text: product?['description']?.toString() ?? '');
    final price = TextEditingController(text: product == null ? '' : (((product['price_minor'] as num?)?.toInt() ?? 0)).toString());
    final stock = TextEditingController(text: product == null ? '0' : (((product['stock_on_hand'] as num?)?.toInt() ?? 0)).toString());
    String kind = product?['kind']?.toString() ?? 'shopping';
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: Text(product == null ? 'Add product' : 'Edit product'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Product name')),
        const SizedBox(height: 8), TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 8), DropdownButtonFormField<String>(value: kind, decoration: const InputDecoration(labelText: 'Catalogue type'),
          items: const [DropdownMenuItem(value:'shopping',child:Text('Shopping')),DropdownMenuItem(value:'food',child:Text('Food')),DropdownMenuItem(value:'quick',child:Text('Quick commerce'))],
          onChanged: (v) { if (v != null) setDialog(() => kind = v); }),
        const SizedBox(height: 8), TextField(controller: price, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Price in paise', helperText: '₹100.00 is 10000 paise.')),
        const SizedBox(height: 8), TextField(controller: stock, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Stock on hand', helperText: 'Quantity available now. Cannot be lower than reserved stock.')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, {'name':name.text.trim(),'description':description.text.trim(),'kind':kind,'price':int.tryParse(price.text.trim()),'stock':int.tryParse(stock.text.trim())}),
          child: const Text('Save draft'))],
    )));
    name.dispose(); description.dispose(); price.dispose(); stock.dispose();
    if (result == null || !mounted) return;
    final amount = result['price'] as int?;
    final stockCount = result['stock'] as int?;
    if ((result['name'] as String).length < 1 || amount == null || amount <= 0 || stockCount == null || stockCount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a product name, positive price in paise and non-negative stock.')));
      return;
    }
    try {
      final values = {'name':result['name'],'description':result['description'],'kind':result['kind'],'price_minor':amount,'currency':'INR'};
      String productId;
      if (product == null) {
        final saved = await widget.client.from('seller_products').insert({...values,'seller_id':_sellerId}).select('id').single();
        productId = saved['id'].toString();
      } else {
        productId = product['id'].toString();
        await widget.client.from('seller_products').update({...values,'updated_at':DateTime.now().toUtc().toIso8601String()}).eq('id', productId);
      }
      await widget.client.rpc('seller_set_stock', params: {'p_seller_id':_sellerId,'p_product_id':productId,'p_stock_on_hand':stockCount});
      if (mounted) {
        setState(_refresh);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product saved as a draft. An administrator must activate it for customers.')));
      }
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save this product.')));
    }
  }
  Future<void> _orderAction(Map<String, dynamic> order, String action) async {
    try {
      await widget.client.rpc('seller_update_order_status', params: {'p_order_id':order['id'],'p_action':action});
      if (mounted) { setState(_refresh); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Order updated: ' + action))); }
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update this order.')));
    }
  }
  @override
  Widget build(BuildContext context) {
    final pages = [
      _ProductsTab(future:_products, onRefresh:() => setState(_refresh), onAdd:() => _editProduct(), onEdit:(p) => _editProduct(product:p)),
      _SellerOrdersTab(future:_orders, onRefresh:() => setState(_refresh), onAction:_orderAction),
      _SellerProfileTab(seller:widget.seller, client:widget.client),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.seller['display_name']?.toString() ?? 'My shop', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions:[IconButton(tooltip:'Refresh',onPressed:()=>setState(_refresh),icon:const Icon(Icons.refresh)),IconButton(tooltip:'Sign out',onPressed:() async => widget.client.auth.signOut(),icon:const Icon(Icons.logout))]),
      body: IndexedStack(index:_tab,children:pages),
      bottomNavigationBar: NavigationBar(selectedIndex:_tab,onDestinationSelected:(v)=>setState(()=>_tab=v),destinations:const [
        NavigationDestination(icon:Icon(Icons.inventory_2_outlined),selectedIcon:Icon(Icons.inventory_2),label:'Products'),
        NavigationDestination(icon:Icon(Icons.receipt_long_outlined),selectedIcon:Icon(Icons.receipt_long),label:'Orders'),
        NavigationDestination(icon:Icon(Icons.store_outlined),selectedIcon:Icon(Icons.store),label:'Shop'),
      ]),
    );
  }
}

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({required this.future,required this.onRefresh,required this.onAdd,required this.onEdit});
  final Future<List<Map<String,dynamic>>> future;
  final VoidCallback onRefresh, onAdd;
  final ValueChanged<Map<String,dynamic>> onEdit;
  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh:() async => onRefresh(),child:ListView(padding:const EdgeInsets.all(16),children:[
    Row(children:[Expanded(child:Text('Your products',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),
      ),FilledButton.tonalIcon(onPressed:onAdd,icon:const Icon(Icons.add),label:const Text('Add'))]),
    const SizedBox(height:6),const Text('New listings start as drafts. Alteo activates approved listings for the customer catalogue.'),
    FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));
      if(snapshot.hasError)return const Text('Could not load products. Refresh and retry.');
      final rows=snapshot.data??[];
      if(rows.isEmpty)return const _SellerNotice(title:'No products yet',detail:'Add your first listing to build your catalogue.');
      return Column(children:rows.map((p){
        final price=((p['price_minor'] as num?)?.toInt()??0)/100;
        return Card(child:ListTile(
          leading:const CircleAvatar(child:Icon(Icons.inventory_2_outlined)),
          title:Text(p['name'].toString()),
          subtitle:Text('₹'+price.toStringAsFixed(2)+' • '+p['kind'].toString()+' • '+p['status'].toString()+' • stock '+p['stock_on_hand'].toString()),
          trailing:IconButton(onPressed:()=>onEdit(p),icon:const Icon(Icons.edit_outlined)),
        ));
      }).toList());
    }),
  ]));
}

class _SellerOrdersTab extends StatelessWidget {
  const _SellerOrdersTab({required this.future,required this.onRefresh,required this.onAction});
  final Future<List<Map<String,dynamic>>> future;
  final VoidCallback onRefresh;
  final Future<void> Function(Map<String,dynamic>,String) onAction;
  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh:() async => onRefresh(),child:ListView(padding:const EdgeInsets.all(16),children:[
    Text('Orders',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),
    const SizedBox(height:6),const Text('Processing requires confirmed payment. Payment-provider integration is not active yet.'),
    FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));
      if(snapshot.hasError)return const Text('Could not load orders.');
      final rows=snapshot.data??[];
      if(rows.isEmpty)return const _SellerNotice(title:'No orders yet',detail:'Orders for your approved shop will appear here.');
      return Column(children:rows.map((o){
        final status=o['status'].toString(),payment=o['payment_status'].toString();
        final total=((o['total_minor'] as num?)?.toInt()??0)/100;
        return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Order '+o['id'].toString().substring(0,8).toUpperCase(),style:const TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:4),Text(status.replaceAll('_',' ')+' • Payment: '+payment+' • ₹'+total.toStringAsFixed(2)),
          if(payment=='paid')Wrap(spacing:8,children:[
            if(status=='paid')TextButton(onPressed:()=>onAction(o,'accept'),child:const Text('Accept')),
            if(status=='accepted')TextButton(onPressed:()=>onAction(o,'prepare'),child:const Text('Start preparing')),
            if(status=='preparing')FilledButton.tonal(onPressed:()=>onAction(o,'ready'),child:const Text('Ready for pickup')),
          ]),
        ])));
      }).toList());
    }),
  ]));
}

class _SellerProfileTab extends StatelessWidget {
  const _SellerProfileTab({required this.seller,required this.client});
  final Map<String,dynamic> seller;
  final SupabaseClient client;
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    Text('Shop profile',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),
    Card(child:Column(children:[
      ListTile(leading:const Icon(Icons.storefront_outlined),title:Text(seller['display_name'].toString()),subtitle:const Text('Approved seller')),
      ListTile(leading:const Icon(Icons.phone_outlined),title:Text(seller['phone']?.toString()??'No phone')),
      ListTile(leading:const Icon(Icons.email_outlined),title:Text(seller['contact_email']?.toString()??'No email')),
    ])),
    const _SellerNotice(title:'Operations reminder',detail:'Maintain accurate stock and prices. Listings remain hidden until an administrator activates them.'),
    const SizedBox(height:14),OutlinedButton.icon(onPressed:() async=>client.auth.signOut(),icon:const Icon(Icons.logout),label:const Text('Sign out')),
  ]);
}
class _SellerNotice extends StatelessWidget {
  const _SellerNotice({required this.title,required this.detail});
  final String title,detail;
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(18),child:Column(children:[
    const Icon(Icons.info_outline,size:38),const SizedBox(height:8),
    Text(title,style:const TextStyle(fontWeight:FontWeight.w800),textAlign:TextAlign.center),
    const SizedBox(height:6),Text(detail,textAlign:TextAlign.center),
  ]));
}
