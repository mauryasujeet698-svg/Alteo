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
  final rows=await client.from('cart_items').select('id,quantity,product_id,seller_products(name,price_minor,image_url)').eq('cart_id',cart['id']).order('created_at');
  return (rows as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
 }

 Future<void> checkout() async {
  final address = TextEditingController();
  try {
   final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
    title: const Text('Delivery address'),
    content: TextField(
     controller: address,
     minLines: 2,
     maxLines: 4,
     decoration: const InputDecoration(labelText: 'Full delivery address', hintText: 'House, street, area, city, PIN code', border: OutlineInputBorder()),
    ),
    actions: [
     TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
     FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Place COD order')),
    ],
   ));
   if (confirmed != true || !mounted) return;
   if (address.text.trim().length < 8) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a complete delivery address.')));
    return;
   }
   try {
    final result = await Supabase.instance.client.rpc('create_orders_from_cart', params: {
     'delivery_address': {'address_line': address.text.trim()},
     'customer_note': '',
    });
    if (!mounted) return;
    final count = result is List ? result.length : 1;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(count == 1 ? 'Order placed. Cash on delivery.' : count.toString() + ' seller orders placed. Cash on delivery.')));
    setState(() => items = load());
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerOrdersPage()));
   } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not place order. Confirm the checkout migration is applied and stock is available. ' + e.toString())));
   }
  } finally {
   address.dispose();
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
    SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Subtotal',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),Text('₹${(total/100).toStringAsFixed(0)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),const SizedBox(height:10),const Text('Cash on delivery. Your address and stock availability are validated before the order is created.',style:TextStyle(fontSize:12,color:Color(0xFF737B76))),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton(onPressed:checkout,child:const Text('Place order · Cash on delivery')))])))
   ]);
  }));
 }
}