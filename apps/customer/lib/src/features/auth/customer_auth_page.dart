import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAuthPage extends StatefulWidget {
  const CustomerAuthPage({super.key});
  @override
  State<CustomerAuthPage> createState() => _CustomerAuthPageState();
}

class _CustomerAuthPageState extends State<CustomerAuthPage> {
  final phone = TextEditingController();
  final email = TextEditingController();
  final code = TextEditingController();
  bool useEmail = false;
  bool sent = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    email.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    final value = useEmail ? email.text.trim() : phone.text.trim();
    if (useEmail) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
        setState(() => error = 'Enter a valid email address.');
        return;
      }
    } else if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)) {
      setState(() => error = 'Enter your phone number with country code, e.g. +919876543210.');
      return;
    }

    setState(() { busy = true; error = null; });
    try {
      if (useEmail) {
        await Supabase.instance.client.auth.signInWithOtp(email: value);
      } else {
        await Supabase.instance.client.auth.signInWithOtp(phone: value);
      }
      if (mounted) setState(() { sent = true; error = useEmail ? 'Verification code sent to your email.' : 'Verification code sent by SMS.'; });
    } on AuthException catch (e) {
      if (!mounted) return;
      final lower = e.message.toLowerCase();
      setState(() => error = lower.contains('provider is not enabled') || lower.contains('unsupported provider')
        ? (useEmail ? 'Email authentication is not enabled in Supabase. Switch to phone if Phone Auth is configured, or ask the project owner to enable a provider.' : 'Phone authentication is not enabled in Supabase. Switch to email if email authentication is configured. Browsing remains available.')
        : e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not send the code. Check authentication configuration. You can still explore without signing in.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyCode() async {
    if (code.text.trim().isEmpty) {
      setState(() => error = 'Enter the verification code.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      if (useEmail) {
        await Supabase.instance.client.auth.verifyOTP(email: email.text.trim(), token: code.text.trim(), type: OtpType.email);
      } else {
        await Supabase.instance.client.auth.verifyOTP(phone: phone.text.trim(), token: code.text.trim(), type: OtpType.sms);
      }
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8F6),
    appBar: AppBar(title: const Text('Sign in')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Container(height: 70, width: 70, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF176B57), borderRadius: BorderRadius.circular(22)), child: const Icon(Icons.explore_rounded, size: 40, color: Colors.white)),
      const SizedBox(height: 24),
      const Text('Welcome to Alteo', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Explore services, shopping and local essentials. Sign-in is only needed for account-specific actions.', style: TextStyle(color: Color(0xFF68736D), height: 1.5)),
      const SizedBox(height: 20),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(
        onPressed: busy || sent ? null : () => setState(() { useEmail = !useEmail; error = null; }),
        icon: Icon(useEmail ? Icons.phone_android : Icons.email_outlined),
        label: Text(useEmail ? 'Use phone instead' : 'Use email instead'),
      )),
      TextField(
        controller: useEmail ? email : phone,
        enabled: !sent,
        keyboardType: useEmail ? TextInputType.emailAddress : TextInputType.phone,
        decoration: InputDecoration(
          labelText: useEmail ? 'Email address' : 'Phone number',
          hintText: useEmail ? 'you@example.com' : '+919876543210',
          prefixIcon: Icon(useEmail ? Icons.email_outlined : Icons.phone_android),
          border: const OutlineInputBorder(),
          filled: true,
        ),
      ),
      if (sent) ...[
        const SizedBox(height: 14),
        TextField(controller: code, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: useEmail ? 'Email verification code' : 'SMS code', prefixIcon: const Icon(Icons.verified_user_outlined), border: const OutlineInputBorder(), filled: true)),
      ],
      if (error != null) ...[
        const SizedBox(height: 12),
        Text(error!, style: TextStyle(color: error!.contains('sent') ? Colors.green : Colors.red, height: 1.4)),
      ],
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy ? null : (sent ? verifyCode : sendCode),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF176B57), minimumSize: const Size.fromHeight(52)),
        child: Text(busy ? 'Please wait…' : sent ? 'Verify and sign in' : 'Send verification code'),
      ),
      if (sent) TextButton(onPressed: busy ? null : () => setState(() { sent = false; code.clear(); error = null; }), child: const Text('Change contact')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: busy ? null : () => Navigator.of(context).pop(false), icon: const Icon(Icons.explore_outlined), label: const Text('Explore without signing in'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50))),
      const SizedBox(height: 16),
      const Text('Browsing is public. Sign-in requires a configured email or phone authentication provider in Supabase.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF68736D), fontSize: 12, height: 1.5)),
    ]),
  );
}
