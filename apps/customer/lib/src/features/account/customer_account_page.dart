import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';

class CustomerAccountPage extends StatefulWidget {
 const CustomerAccountPage({super.key});
 @override State<CustomerAccountPage> createState()=>_CustomerAccountPageState();
}
class _CustomerAccountPageState extends State<CustomerAccountPage> {
 bool busy=false;
 @override Widget build(BuildContext context){
  final user=Supabase.instance.client.auth.currentUser;
  return Scaffold(appBar:AppBar(title:const Text('My account')),body:ListView(padding:const EdgeInsets.all(20),children:[
   Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(22),border:Border.all(color:const Color(0xFFE7EBE7))),child:Row(children:[
    const CircleAvatar(radius:29,backgroundColor:Color(0xFFE1F2E9),child:Icon(Icons.person_rounded,color:Color(0xFF176B57),size:32)),const SizedBox(width:14),
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text(user==null?'Welcome to Alteo':'You’re signed in',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
     const SizedBox(height:5),Text(user?.phone ?? user?.email ?? 'Sign in to manage your account',style:const TextStyle(color:Color(0xFF737B76),fontSize:12))
    ]))
   ])),
   const SizedBox(height:16),
   if(user==null) FilledButton.icon(onPressed:()=>Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>const CustomerAuthPage())).then((_) {if(mounted)setState((){});}),icon:const Icon(Icons.login_rounded),label:const Text('Sign in / Create account'),style:FilledButton.styleFrom(backgroundColor:const Color(0xFF176B57),minimumSize:const Size.fromHeight(52)))
   else OutlinedButton.icon(onPressed:busy?null:()async{setState(()=>busy=true);try{await Supabase.instance.client.auth.signOut();}finally{if(mounted)setState(()=>busy=false);}},icon:const Icon(Icons.logout_rounded),label:Text(busy?'Signing out…':'Sign out')),
   const SizedBox(height:18),
   _row(context,Icons.location_on_outlined,'Saved addresses','Manage home, work and other places','Sign in to manage saved addresses.'),
   _row(context,Icons.receipt_long_rounded,'Orders & activity','Track your purchases and services','Order history will appear after order checkout is connected.'),
   _row(context,Icons.payment_rounded,'Payments','Payment methods and transactions','Payment options will be enabled after a payment provider is configured.'),
   _row(context,Icons.support_agent_rounded,'Help & support','Get help with Alteo services','Support channels will be published before public launch.'),
   _row(context,Icons.privacy_tip_outlined,'Privacy & terms','How Alteo handles your information','Publish final privacy policy and terms before public launch.'),
   const SizedBox(height:12),
   const Text('Secure sign-in uses Supabase Auth. Phone OTP requires an SMS provider configured in the Supabase dashboard.',style:TextStyle(color:Color(0xFF737B76),height:1.5,fontSize:12))
  ]));
 }
 Widget _row(BuildContext context,IconData icon,String title,String subtitle,String message)=>Card(color:Colors.white,elevation:0,margin:const EdgeInsets.only(bottom:9),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(17),side:const BorderSide(color:Color(0xFFE7EBE7))),child:ListTile(leading:Icon(icon,color:const Color(0xFF176B57)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(subtitle,style:const TextStyle(fontSize:12)),trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>showDialog<void>(context:context,builder:(context)=>AlertDialog(title:Text(title),content:Text(message),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Got it'))]))));
}