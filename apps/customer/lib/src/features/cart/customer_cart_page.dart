import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';

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
 @override Widget build(BuildContext context){
  final signedIn=Supabase.instance.client.auth.currentUser!=null;
  return Scaffold(appBar:AppBar(title:const Text('Your cart'),actions:[IconButton(onPressed:()=>setState(()=>items=load()),icon:const Icon(Icons.refresh))]),body:!signedIn?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.shopping_cart_outlined,size:54),const SizedBox(height:12),const Text('Sign in to view your cart'),const SizedBox(height:12),FilledButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CustomerAuthPage())).then((_)=>setState(()=>items=load())),child:const Text('Sign in'))]))):FutureBuilder<List<Map<String,dynamic>>>(future:items,builder:(context,s){
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
    SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Subtotal',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),Text('₹${(total/100).toStringAsFixed(0)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),const SizedBox(height:10),const Text('Checkout will be enabled after delivery fees, address validation and payment/order creation are configured.',style:TextStyle(fontSize:12,color:Color(0xFF737B76))),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton(onPressed:null,child:const Text('Checkout not enabled yet')))])))
   ]);
  }));
 }
}