import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';
import '../orders/customer_orders_page.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/mapbox_service.dart';

class CustomerCartPage extends StatefulWidget {
 const CustomerCartPage({super.key});
 @override State<CustomerCartPage> createState()=>_CustomerCartPageState();
}
class _CustomerCartPageState extends State<CustomerCartPage>{
 late Future<List<Map<String,dynamic>>> items;
 @override void initState(){super.initState();items=load();}
 Future<List<Map<String,dynamic>>> load()async{
  final client=Supabase.instance.client;
  final user=client.auth.currentUser;
  if(user==null)return [];
  final cart=await client.from('carts').select('id').eq('customer_id',user.id).eq('status','active').maybeSingle();
  if(cart==null)return [];
  final rows=await client.from('cart_items').select('id,quantity,product_id,seller_products(name,price_minor,image_url,seller_id,kind)').eq('cart_id',cart['id']).order('created_at');
  return (rows as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
 }

 Future<void> checkout() async {
  final recipient = TextEditingController();
  final phone = TextEditingController();
  final addressLine = TextEditingController();
  final city = TextEditingController();
  final stateName = TextEditingController();
  final postalCode = TextEditingController();
  final label = TextEditingController(text: 'Home');
  bool saveAddress = false;
  bool locating = false;
  String selectedPaymentMethod = 'cod';
  List<Map<String, dynamic>> savedAddresses = [];
  Map<String, dynamic>? selectedAddress;
  try {
   final userForAddresses = Supabase.instance.client.auth.currentUser;
   if (userForAddresses != null) {
    try {
     final rows = await Supabase.instance.client.from('addresses').select('id,label,recipient_name,phone,address_line1,locality,city,state,postal_code,latitude,longitude,is_default').eq('user_id', userForAddresses.id).order('is_default', ascending: false);
     savedAddresses = (rows as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    } catch (_) { /* Manual entry remains available if saved addresses cannot load. */ }
   }
   final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
    title: const Text('Delivery details'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
     if (savedAddresses.isNotEmpty) DropdownButtonFormField<String>(
      value: selectedAddress?['id']?.toString(),
      decoration: const InputDecoration(labelText: 'Use a saved address'),
      items: savedAddresses.map((address) => DropdownMenuItem<String>(
       value: address['id'].toString(),
       child: Text('${address['label'] ?? 'Saved address'}', overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: (id) {
       final matches = savedAddresses.where((address) => address['id'].toString() == id).toList();
       if (matches.isEmpty) return;
       final match = matches.first;
       setDialogState(() {
        selectedAddress = match;
        recipient.text = (match['recipient_name'] ?? '').toString();
        phone.text = (match['phone'] ?? '').toString();
        addressLine.text = (match['address_line1'] ?? '').toString();
        city.text = (match['city'] ?? '').toString();
        stateName.text = (match['state'] ?? '').toString();
        postalCode.text = (match['postal_code'] ?? '').toString();
       });
      },
     ),
     Align(alignment: Alignment.centerLeft, child: TextButton.icon(
      onPressed: locating ? null : () async {
       setDialogState(() => locating = true);
       try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
         throw StateError('Allow location access in Android settings to use your current location.');
        }
        final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)).timeout(const Duration(seconds: 15));
        final place = await MapboxService.reverseGeocode(position.longitude, position.latitude);
        addressLine.text = place ?? '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        setDialogState(() {});
       } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get current location: $e')));
       } finally { setDialogState(() => locating = false); }
      },
      icon: locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
      label: Text(locating ? 'Getting location…' : 'Use current location'),
     )),
     TextField(controller: recipient, decoration: const InputDecoration(labelText: 'Recipient name')),
     TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
     TextField(controller: addressLine, minLines: 1, maxLines: 2, decoration: const InputDecoration(labelText: 'House and street')),
     TextField(controller: city, decoration: const InputDecoration(labelText: 'City')),
     TextField(controller: stateName, decoration: const InputDecoration(labelText: 'State')),
     TextField(controller: postalCode, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN code')),
     TextField(controller: label, decoration: const InputDecoration(labelText: 'Save address as (optional)')),
     CheckboxListTile(contentPadding: EdgeInsets.zero, value: saveAddress, onChanged: (value) => setDialogState(() => saveAddress = value ?? false), title: const Text('Save these details for next time')),
     const SizedBox(height: 12),
     const Align(alignment: Alignment.centerLeft, child: Text('Payment method', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
     const SizedBox(height: 4),
     RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      value: 'cod',
      groupValue: selectedPaymentMethod,
      onChanged: (value) => setDialogState(() => selectedPaymentMethod = value ?? 'cod'),
      title: const Text('Cash on delivery'),
      subtitle: const Text('Pay in cash when your order arrives'),
      secondary: const Icon(Icons.payments_outlined, color: Color(0xFF176B57)),
     ),
     const Divider(height: 4),
     const ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.account_balance_rounded, color: Color(0xFF9AA39D)),
      title: Text('UPI', style: TextStyle(color: Color(0xFF7D8780))),
      subtitle: Text('Coming soon'),
      trailing: Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF9AA39D)),
      dense: true,
     ),
     const ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.credit_card_rounded, color: Color(0xFF9AA39D)),
      title: Text('Cards, wallets and net banking', style: TextStyle(color: Color(0xFF7D8780))),
      subtitle: Text('Not available yet'),
      trailing: Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF9AA39D)),
      dense: true,
     ),
    ])),
    actions: [
     TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
     FilledButton(onPressed: selectedPaymentMethod == 'cod' ? () => Navigator.pop(dialogContext, true) : null, child: const Text('Place order')),
    ],
   )));
   if (confirmed != true || !mounted) return;
   if (recipient.text.trim().length < 2 || phone.text.trim().length < 8 ||
       addressLine.text.trim().length < 3 || city.text.trim().length < 2 ||
       stateName.text.trim().length < 2 || postalCode.text.trim().length < 5) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Complete all delivery details before continuing.')));
    return;
   }

   final client = Supabase.instance.client;
   final user = client.auth.currentUser;
   if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in is required to place an order. You can keep exploring without signing in.')));
    return;
   }
   if (saveAddress && selectedAddress == null) {
    try {
     await client.from('addresses').insert({
      'user_id': user.id,
      'label': label.text.trim().isEmpty ? 'Home' : label.text.trim(),
      'recipient_name': recipient.text.trim(),
      'phone': phone.text.trim(),
      'address_line1': addressLine.text.trim(),
      'city': city.text.trim(),
      'state': stateName.text.trim(),
      'postal_code': postalCode.text.trim(),
      'is_default': false,
     });
    } catch (e) {
     if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('Address could not be saved. Your order was not submitted. Please check your connection and address permissions, then try again. $e')),
      );
     }
     return;
    }
   }
   final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
   if (cart == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your cart is empty.')));
    return;
   }
   final currentItems = await load();
   if (currentItems.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your cart is empty.')));
    return;
   }
   final groups = <String, List<Map<String, dynamic>>>{};
   for (final row in currentItems) {
    final product = row['seller_products'] as Map? ?? {};
    final groupKey = (product['seller_id']?.toString() ?? '') + '|' + (product['kind']?.toString() ?? '');
    groups.putIfAbsent(groupKey, () => <Map<String, dynamic>>[]).add(row);
   }

   try {
    var createdCount = 0;
    var groupIndex = 0;
    for (final group in groups.values) {
     final payload = group.map((row) => <String, dynamic>{
      'product_id': row['product_id'],
      'quantity': row['quantity'],
     }).toList();
     await client.rpc('create_customer_order', params: {
      'p_items': payload,
      'p_delivery_address': {
       'recipient_name': recipient.text.trim(),
       'phone': phone.text.trim(),
       'address_line1': addressLine.text.trim(),
       'city': city.text.trim(),
       'state': stateName.text.trim(),
       'postal_code': postalCode.text.trim(),
       'area_code': 'DEFAULT',
      },
      'p_idempotency_key': 'cart-' + cart['id'].toString() + '-' + groupIndex.toString(),
      'p_payment_method': selectedPaymentMethod,
     });
     createdCount++;
     groupIndex++;
    }
    await client.from('carts').delete().eq('id', cart['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(createdCount.toString() + (createdCount == 1 ? ' order placed with Cash on Delivery. Please pay when it arrives.' : ' orders placed with Cash on Delivery. Please pay when they arrive.'))));
    setState(() => items = load());
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerOrdersPage()));
   } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create all orders. Check service availability, pricing and payment setup. Retry is safe for orders already created. ' + e.toString())));
   }
  } finally {
   recipient.dispose();
   phone.dispose();
   addressLine.dispose();
   city.dispose();
   stateName.dispose();
   postalCode.dispose();
   label.dispose();
  }
 }

 @override Widget build(BuildContext context){
  final signedIn=Supabase.instance.client.auth.currentUser!=null;
  return Scaffold(appBar:AppBar(title:const Text('Your cart'),actions:[IconButton(onPressed:()=>setState(()=>items=load()),icon:const Icon(Icons.refresh))]),body:!signedIn?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.shopping_cart_outlined,size:54,color:Color(0xFF176B57)),const SizedBox(height:12),const Text('Your cart is ready when you are',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800),textAlign:TextAlign.center),const SizedBox(height:8),const Text('You can keep exploring Alteo without signing in. Sign in only when you want to save a cart or continue to checkout.',textAlign:TextAlign.center,style:TextStyle(height:1.45)),const SizedBox(height:14),FilledButton(onPressed:()=>Navigator.of(context).pop(),child:const Text('Continue exploring')),TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CustomerAuthPage())).then((_)=>setState(()=>items=load())),child:const Text('Sign in when ready'))]))):FutureBuilder<List<Map<String,dynamic>>>(future:items,builder:(context,s){
   if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
   if(s.hasError)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Could not load your cart. Pull refresh to try again.')));
   final list=s.data??[];
   if(list.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.shopping_basket_outlined,size:56,color:Color(0xFF176B57)),SizedBox(height:14),Text('Your cart is empty',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800)),SizedBox(height:6),Text('Add items from the home catalogue to see them here.',textAlign:TextAlign.center)])));
   var total=0;
   for(final row in list){final p=row['seller_products'] as Map?;total+=(((p?['price_minor'] as num?)?.toInt()??0)*(row['quantity'] as int? ??1));}
   return Column(children:[
    Expanded(child:ListView.separated(padding:const EdgeInsets.all(16),itemCount:list.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(context,i){
     final row=list[i],p=(row['seller_products'] as Map?)??{};
     return Card(elevation:0,color:Colors.white,child:ListTile(title:Text((p['name'] as String?)??'Item',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Qty: ${row['quantity']}'),trailing:Text('₹${((((p['price_minor'] as num?)?.toInt()??0)*(row['quantity'] as int? ??1))/100).toStringAsFixed(0)}',style:const TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF176B57)))));
    })),
    SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Subtotal',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),Text('₹${(total/100).toStringAsFixed(0)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),const SizedBox(height:10),const Text('Cash on delivery is available now. UPI, cards, wallets and net banking are coming soon.',style:TextStyle(fontSize:12,color:Color(0xFF737B76))),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton(onPressed:checkout,child:const Text('Checkout · Cash on delivery')))])))
   ]);
  }));
 }
}