import 'package:flutter/material.dart';

class CustomerAccountPage extends StatelessWidget {
  const CustomerAccountPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My account')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE7EBE7))),
          child: const Row(children: [
            CircleAvatar(radius: 29, backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.person_rounded, color: Color(0xFF176B57), size: 32)),
            SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Welcome to Alteo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 5),
              Text('Your everyday services, in one place', style: TextStyle(color: Color(0xFF737B76), fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 18),
        _AccountRow(icon: Icons.location_on_outlined, title: 'Saved addresses', subtitle: 'Manage home, work and other places', onTap: () => _message(context, 'Saved addresses', 'Address saving will be available when your profile backend is connected.')),
        _AccountRow(icon: Icons.payment_rounded, title: 'Payments', subtitle: 'Payment methods and transactions', onTap: () => _message(context, 'Payments', 'No payment method is connected yet.')),
        _AccountRow(icon: Icons.support_agent_rounded, title: 'Help & support', subtitle: 'Get help with Alteo services', onTap: () => _message(context, 'Help & support', 'Support channels will be added before launch.')),
        _AccountRow(icon: Icons.privacy_tip_outlined, title: 'Privacy & terms', subtitle: 'How Alteo handles your information', onTap: () => _message(context, 'Privacy & terms', 'The final legal pages must be published before public launch.')),
        const SizedBox(height: 14),
        const Text('Customer sign-in is not enabled yet. Supabase Auth and phone OTP must be configured before account features can be activated.', style: TextStyle(color: Color(0xFF737B76), height: 1.5)),
      ],
    ),
  );

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