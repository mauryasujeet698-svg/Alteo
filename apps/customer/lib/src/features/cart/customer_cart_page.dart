import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';
import '../orders/customer_orders_page.dart';

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
  try {
   final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
    title: const Text('Delivery details'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
     TextField(controller: recipient, decoration: const InputDecoration(labelText: 'Recipient name')),
     TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
     TextField(controller: addressLine, minLines: 1, maxLines: 2, decoration: const InputDecoration(labelText: 'House and street')),
     TextField(controller: city, decoration: const InputDecoration(labelText: 'City')),
     TextField(controller: stateName, decoration: const InputDecoration(labelText: 'State')),
     TextField(controller: postalCode, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN code')),
    ])),
    actions: [
     TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
     FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create order')),
    ],
   ));
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
     });
     createdCount++;
     groupIndex++;
    }
    await client.from('carts').delete().eq('id', cart['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(createdCount.toString() + (createdCount == 1 ? ' order created. Payment is still required before fulfilment begins.' : ' seller/category orders created. Payment is still required before fulfilment begins.'))));
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
    SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Subtotal',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),Text('₹${(total/100).toStringAsFixed(0)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),const SizedBox(height:10),const Text('The backend validates your address, prices and service availability. Payment is required before fulfilment begins.',style:TextStyle(fontSize:12,color:Color(0xFF737B76))),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton(onPressed:checkout,child:const Text('Create order · Payment required')))])))
   ]);
  }));
 }
}