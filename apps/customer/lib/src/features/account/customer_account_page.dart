import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAccountPage extends StatelessWidget {
  const CustomerAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final hasBackend = Supabase.instance.isInitialized;
    final user = hasBackend ? Supabase.instance.client.auth.currentUser : null;
    final email = user?.email;
    return Scaffold(
      appBar: AppBar(title: const Text('My account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE7EBE7))),
            child: Row(
              children: [
                Container(height: 58, width: 58, decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(19)), child: const Icon(Icons.person_rounded, color: Color(0xFF176B57), size: 32)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(email == null ? 'Welcome to Alteo' : 'Signed in', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(email ?? 'Your profile and preferences', style: const TextStyle(color: Color(0xFF737B76), fontSize: 12)),
                ])),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _AccountRow(icon: Icons.location_on_outlined, title: 'Saved addresses', subtitle: 'Manage home, work and other places', onTap: () => _message(context, 'Saved addresses', 'Address saving will be available when your profile backend is connected.')),
          _AccountRow(icon: Icons.payment_rounded, title: 'Payments', subtitle: 'Payment methods and transactions', onTap: () => _message(context, 'Payments', 'No payment method is connected yet.')),
          _AccountRow(icon: Icons.support_agent_rounded, title: 'Help & support', subtitle: 'Get help with Alteo services', onTap: () => _message(context, 'Help & support', 'Support channels will be added before launch.')),
          _AccountRow(icon: Icons.privacy_tip_outlined, title: 'Privacy & terms', subtitle: 'How Alteo handles your information', onTap: () => _message(context, 'Privacy & terms', 'The final legal pages must be published before public launch.')),
          if (user != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () async { await Supabase.instance.client.auth.signOut(); if (context.mounted) Navigator.of(context).pop(); }, icon: const Icon(Icons.logout_rounded), label: const Text('Sign out')),
          ] else ...[
            const SizedBox(height: 14),
            const Text('Sign-in is not enabled in this build. Connect Supabase Auth and configure phone OTP before enabling customer accounts.', style: TextStyle(color: Color(0xFF737B76), height: 1.5)),
          ],
        ],
      ),
    );
  }

  static void _message(BuildContext context, String title, String message) {
    showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))]));
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: const BorderSide(color: Color(0xFFE7EBE7))),
    child: ListTile(leading: Icon(icon, color: const Color(0xFF176B57)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)), trailing: const Icon(Icons.chevron_right_rounded), onTap: onTap),
  );
}