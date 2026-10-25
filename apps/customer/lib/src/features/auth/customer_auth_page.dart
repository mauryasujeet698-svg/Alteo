import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
Future<void>? _googleSignInInitialization;

class CustomerAuthPage extends StatefulWidget {
  const CustomerAuthPage({super.key});
  @override
  State<CustomerAuthPage> createState() => _CustomerAuthPageState();
}

class _CustomerAuthPageState extends State<CustomerAuthPage> {
  bool busy = false;
  String? message;
  StreamSubscription<AuthState>? authSubscription;

  @override
  void initState() {
    super.initState();
    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn && mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  Future<void> signInWithGoogle() async {
    setState(() { busy = true; message = null; });
    try {
      if (googleWebClientId.isEmpty) {
        throw const AuthException('Google native sign-in is not configured yet. Please set GOOGLE_WEB_CLIENT_ID in the release build.');
      }
      _googleSignInInitialization ??= GoogleSignIn.instance.initialize(
        serverClientId: googleWebClientId,
      );
      await _googleSignInInitialization;
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuthentication = googleUser.authentication;
      final idToken = googleAuthentication.idToken;
      if (idToken == null) {
        throw const AuthException('Google did not return an ID token. Check the Android OAuth client and signing SHA-1.');
      }
      final authorization = await googleUser.authorizationClient
          .authorizationForScopes(const ['email']);
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization?.accessToken,
      );
      if (mounted) {
        setState(() => message = 'Google sign-in completed. Finishing your Alteo session…');
      }
    } catch (e) {
      if (!mounted) return;
      final lower = e.toString().toLowerCase();
      setState(() => message = lower.contains('canceled') || lower.contains('cancelled')
          ? 'Google sign-in was cancelled.'
          : 'Google sign-in failed: ' + e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8F6),
    appBar: AppBar(title: const Text('Sign in to Alteo')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Container(
        height: 76, width: 76, alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFF176B57), borderRadius: BorderRadius.circular(24)),
        child: const Icon(Icons.explore_rounded, size: 42, color: Colors.white),
      ),
      const SizedBox(height: 24),
      const Text('Welcome to Alteo', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.6)),
      const SizedBox(height: 8),
      const Text('Shop, discover food and book rides. You can explore freely; sign in only when an action needs your account.', style: TextStyle(color: Color(0xFF68736D), height: 1.55)),
      const SizedBox(height: 24),
      SizedBox(
        height: 54,
        child: FilledButton.icon(
          onPressed: busy ? null : signInWithGoogle,
          icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
          label: Text(busy ? 'Connecting to Google…' : 'Continue with Google'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF176B57), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ),
      ),
      if (message != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5EAE5))),
          child: Text(message!, style: const TextStyle(height: 1.45, color: Color(0xFF68736D))),
        ),
      ],
      const SizedBox(height: 12),
      OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continue exploring')),
      const SizedBox(height: 18),
      const Text('By continuing, you agree to Alteo’s Terms and Privacy Policy.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFF737B76))),
    ]),
  );
}
