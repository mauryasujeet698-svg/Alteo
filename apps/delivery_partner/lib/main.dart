import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const appName='Alteo Delivery Partner';
const requiredRole='delivery_partner';
const supabaseUrl=String.fromEnvironment('SUPABASE_URL',defaultValue:'https://nkerkoptbrcadlpxffkn.supabase.co');
const supabaseKey=String.fromEnvironment('SUPABASE_ANON_KEY',defaultValue:'sb_publishable_lM6ttzw8KMPH2BNXgMAJVA_3y1h51YD');

Future<void> main() async {
 WidgetsFlutterBinding.ensureInitialized();
 String? startupError;
 try {
  if(supabaseUrl.isEmpty||supabaseKey.isEmpty) throw StateError('SUPABASE_URL and SUPABASE_ANON_KEY are required.');
  await Supabase.initialize(url:supabaseUrl,publishableKey:supabaseKey);
 } catch(e) { startupError='Supabase could not be initialized. Check the project URL, publishable key, network access and project status.\n\n$e'; }
 runApp(RoleApp(startupError:startupError));
}
class RoleApp extends StatelessWidget {
 const RoleApp({super.key,this.startupError});
 final String? startupError;
 @override Widget build(BuildContext context)=>MaterialApp(title:appName,debugShowCheckedModeBanner:false,theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF176B57)),useMaterial3:true),home:startupError==null?const RoleGate():StartupError(message:startupError!));
}
class StartupError extends StatelessWidget {
 const StartupError({super.key,required this.message}); final String message;
 @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_rounded,size:54,color:Color(0xFF176B57)),const SizedBox(height:18),Text(appName,style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900)),const SizedBox(height:12),Text(message,textAlign:TextAlign.center,style:const TextStyle(height:1.5)),const SizedBox(height:18),const Text('Reopen the app after checking the configuration.',textAlign:TextAlign.center)])))));
}
class RoleGate extends StatefulWidget { const RoleGate({super.key}); @override State<RoleGate> createState()=>_RoleGateState(); }
class _RoleGateState extends State<RoleGate> {
 final phone=TextEditingController(),code=TextEditingController();
 bool sent=false,busy=false;String? error;bool authorized=false;
 @override void dispose(){phone.dispose();code.dispose();super.dispose();}
 Future<void> send() async {
  if(!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone.text.trim())){setState(()=>error='Enter phone with country code, e.g. +919876543210.');return;}
  setState(()=>{busy=true,error=null});
  try{await Supabase.instance.client.auth.signInWithOtp(phone:phone.text.trim());setState(()=>sent=true);}
  catch(e){setState(()=>error='Could not send OTP. Ensure the Supabase phone provider and SMS gateway are configured. $e');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> verify() async {
  setState(()=>{busy=true,error=null});
  try{
   await Supabase.instance.client.auth.verifyOTP(phone:phone.text.trim(),token:code.text.trim(),type:OtpType.sms);
   final user=Supabase.instance.client.auth.currentUser!;
   final row=await Supabase.instance.client.from('user_roles').select('role').eq('user_id',user.id).eq('role',requiredRole).maybeSingle();
   if(row==null){await Supabase.instance.client.auth.signOut();setState(()=>error='This account is not approved for the $requiredRole app. Contact Alteo support.');}
   else setState(()=>authorized=true);
  }catch(e){setState(()=>error='Verification or role check failed: $e');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  if(authorized)return Scaffold(appBar:AppBar(title:Text(appName),actions:[IconButton(onPressed:()async{await Supabase.instance.client.auth.signOut();setState(()=>authorized=false);},icon:const Icon(Icons.logout))]),body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.verified_user_rounded,size:56,color:Color(0xFF176B57)),const SizedBox(height:18),Text('Welcome to $appName',textAlign:TextAlign.center,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:10),Text('Signed in with the required $requiredRole role. Role-specific operations are being connected to the Alteo backend.',textAlign:TextAlign.center,style:const TextStyle(height:1.5))]))));
  return Scaffold(appBar:AppBar(title:Text(appName)),body:ListView(padding:const EdgeInsets.all(24),children:[const Icon(Icons.lock_person_rounded,size:56,color:Color(0xFF176B57)),const SizedBox(height:20),Text('$appName sign in',style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)),const SizedBox(height:8),const Text('Secure phone verification and server-side role checks protect this app.'),const SizedBox(height:24),TextField(controller:phone,enabled:!sent,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone number with country code',hintText:'+919876543210',border:OutlineInputBorder())),if(sent)...[const SizedBox(height:12),TextField(controller:code,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'SMS verification code',border:OutlineInputBorder()))],if(error!=null)...[const SizedBox(height:12),Text(error!,style:const TextStyle(color:Colors.red))],const SizedBox(height:20),FilledButton(onPressed:busy?null:(sent?verify:send),child:Text(busy?'Please wait…':sent?'Verify and continue':'Send OTP'))]));
 }
}
