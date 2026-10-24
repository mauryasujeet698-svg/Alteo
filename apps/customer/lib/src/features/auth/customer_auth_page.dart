import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAuthPage extends StatefulWidget {
 const CustomerAuthPage({super.key});
 @override State<CustomerAuthPage> createState()=>_CustomerAuthPageState();
}
class _CustomerAuthPageState extends State<CustomerAuthPage> {
 final phone=TextEditingController(),code=TextEditingController();
 bool sent=false,busy=false;String? error;
 @override void dispose(){phone.dispose();code.dispose();super.dispose();}
 Future<void> sendCode() async {
  final value=phone.text.trim();
  final digits=value.startsWith('+')?value.substring(1).replaceAll(RegExp(r'[^0-9]'),''):'';
  if(digits.length<8||digits.length>15){setState(()=>error='Enter your phone number with country code, e.g. +919876543210.');return;}
  setState((){busy=true;error=null;});
  try{await Supabase.instance.client.auth.signInWithOtp(phone:value);if(mounted)setState(()=>sent=true);}
  on AuthException catch(e){
   final message=e.message.toLowerCase();
   if(mounted)setState(()=>error=message.contains('provider is not enabled')||message.contains('unsupported provider')
    ?'Phone sign-in is not enabled in Supabase yet. You can still explore Alteo without signing in. Enable Phone Auth and configure an SMS provider before login can work.'
    :message.contains('sms')||message.contains('phone provider')
     ?'Phone sign-in needs an SMS provider enabled in Supabase Auth settings. You can continue exploring without signing in.'
     :e.message);
  }
  catch(_){if(mounted)setState(()=>error='Could not send the code. Check internet and Supabase SMS configuration. You can still explore without signing in.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> verifyCode() async {
  if(code.text.trim().isEmpty){setState(()=>error='Enter the verification code from your SMS.');return;}
  setState((){busy=true;error=null;});
  try{await Supabase.instance.client.auth.verifyOTP(phone:phone.text.trim(),token:code.text.trim(),type:OtpType.sms);if(mounted)Navigator.pop(context,true);}
  on AuthException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Verification failed. Please try again.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(
  backgroundColor:const Color(0xFFF7F8F6),appBar:AppBar(title:const Text('Sign in')),
  body:ListView(padding:const EdgeInsets.all(24),children:[
   Container(height:70,width:70,alignment:Alignment.center,decoration:BoxDecoration(color:const Color(0xFF176B57),borderRadius:BorderRadius.circular(22)),child:const Icon(Icons.explore_rounded,size:40,color:Colors.white)),
   const SizedBox(height:24),const Text('Welcome to Alteo',style:TextStyle(fontSize:29,fontWeight:FontWeight.w900)),
   const SizedBox(height:8),const Text('Explore services, shopping and local essentials. Sign-in is only needed for account-specific actions.',style:TextStyle(color:Color(0xFF68736D),height:1.5)),
   const SizedBox(height:28),TextField(controller:phone,enabled:!sent,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone number',hintText:'+919876543210',prefixIcon:Icon(Icons.phone_android),border:OutlineInputBorder(),filled:true)),
   if(sent)...[const SizedBox(height:14),TextField(controller:code,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'SMS code',prefixIcon:Icon(Icons.verified_user_outlined),border:OutlineInputBorder(),filled:true))],
   if(error!=null)...[const SizedBox(height:12),Text(error!,style:const TextStyle(color:Colors.red,height:1.4))],
   const SizedBox(height:20),FilledButton(onPressed:busy?null:(sent?verifyCode:sendCode),style:FilledButton.styleFrom(backgroundColor:const Color(0xFF176B57),minimumSize:const Size.fromHeight(52)),child:Text(busy?'Please wait…':sent?'Verify and sign in':'Send verification code')),
   if(sent)TextButton(onPressed:busy?null:()=>setState((){sent=false;code.clear();error=null;}),child:const Text('Change phone number')),
   const SizedBox(height:8),
   OutlinedButton.icon(onPressed:busy?null:()=>Navigator.of(context).pop(false),icon:const Icon(Icons.explore_outlined),label:const Text('Explore without signing in'),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(50))),
   const SizedBox(height:16),const Text('Browsing is public. Phone OTP requires Phone Auth and an SMS provider to be configured in Supabase.',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF68736D),fontSize:12,height:1.5))
  ]));
}
