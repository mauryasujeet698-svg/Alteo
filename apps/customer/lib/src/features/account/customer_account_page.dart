import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/customer_preferences.dart';
import '../auth/customer_auth_page.dart';
import '../orders/customer_orders_page.dart';

class CustomerAccountPage extends StatefulWidget {
  const CustomerAccountPage({super.key});
  @override
  State<CustomerAccountPage> createState() => _CustomerAccountPageState();
}

class _CustomerAccountPageState extends State<CustomerAccountPage> {
  bool busy = false;
  SupabaseClient? get client {
    try { return Supabase.instance.client; } catch (_) { return null; }
  }

  Future<void> _signIn() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
    if (mounted) setState(() {});
  }

  Future<void> _chooseTheme() async {
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: alteoThemeMode,
        builder: (context, mode, _) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(alignment: Alignment.centerLeft, child: Text('Appearance', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            const SizedBox(height: 12),
            for (final option in <(String, ThemeMode, IconData)>[
              ('Light', ThemeMode.light, Icons.light_mode_outlined),
              ('Dark', ThemeMode.dark, Icons.dark_mode_outlined),
              ('Follow device', ThemeMode.system, Icons.settings_brightness_outlined),
            ])
              RadioListTile<ThemeMode>(
                value: option.$2, groupValue: mode, title: Text(option.$1), secondary: Icon(option.$3),
                onChanged: (value) { if (value != null) alteoThemeMode.value = value; },
              ),
          ]),
        )),
      ),
    );
  }

  Future<void> _chooseLanguage() async {
    const languages = ['English', 'हिन्दी', 'বাংলা', 'தமிழ்', 'తెలుగు'];
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (context) => ValueListenableBuilder<String>(
        valueListenable: alteoPreferredLanguage,
        builder: (context, language, _) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(alignment: Alignment.centerLeft, child: Text('App language', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            const SizedBox(height: 12),
            for (final option in languages)
              RadioListTile<String>(
                value: option, groupValue: language, title: Text(option),
                onChanged: (value) { if (value != null) alteoPreferredLanguage.value = value; },
              ),
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Language selection is saved for this session; full translation coverage will be added as localisation is completed.', style: TextStyle(fontSize: 12, color: Color(0xFF68736D)))),
          ]),
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = client?.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), centerTitle: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF2C8B70)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(children: [
            const CircleAvatar(radius: 29, backgroundColor: Color(0x33FFFFFF), child: Icon(Icons.person_rounded, color: Colors.white, size: 32)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user == null ? 'Welcome to Alteo' : (user.userMetadata?['full_name']?.toString() ?? 'Your Alteo account'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 5),
              Text(user?.email ?? 'Explore freely. Sign in when you need your account.', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 14),
        if (user == null)
          FilledButton.icon(
            onPressed: _signIn, icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in / Sign up with Google'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF176B57), minimumSize: const Size.fromHeight(52)),
          )
        else
          OutlinedButton.icon(
            onPressed: busy ? null : () async {
              setState(() => busy = true);
              try { await client?.auth.signOut(); } finally { if (mounted) setState(() => busy = false); }
            },
            icon: const Icon(Icons.logout_rounded), label: Text(busy ? 'Signing out…' : 'Sign out'),
          ),
        const SizedBox(height: 22),
        const Text('Your activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        _item(context, Icons.receipt_long_rounded, 'My orders', 'Shopping, food and parcel orders', () {
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerOrdersPage()));
        }),
        _item(context, Icons.directions_car_filled_rounded, 'My rides', 'Ride history and trip details', () => _info('My rides', 'Your completed and active rides will appear here when ride history is available.')),
        _item(context, Icons.location_on_outlined, 'Saved addresses', 'Home, work and other locations', () => _info('Saved addresses', user == null ? 'Sign in with Google to save and manage addresses.' : 'Address management will be connected to your account profile.')),
        _item(context, Icons.favorite_border_rounded, 'Saved items', 'Your favourite products and services', () => _info('Saved items', 'Save products and services for quick access.')),
        const SizedBox(height: 20),
        const Text('Preferences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        _item(context, Icons.palette_outlined, 'Theme', 'Light, dark or follow device settings', _chooseTheme),
        ValueListenableBuilder<String>(
          valueListenable: alteoPreferredLanguage,
          builder: (context, language, _) => _item(context, Icons.language_rounded, 'Language', language, _chooseLanguage),
        ),
        _item(context, Icons.notifications_none_rounded, 'Notifications', 'Order updates and service alerts', () => _info('Notifications', 'Order and ride notifications will be enabled with the notification service.')),
        _item(context, Icons.payments_outlined, 'Payments', 'Payment methods and transactions', () => _info('Payments', 'Payment methods will appear after a payment provider is configured.')),
        _item(context, Icons.support_agent_rounded, 'Help & support', 'Get help with Alteo services', () => _info('Help & support', 'Support contact details will be published before public launch.')),
        _item(context, Icons.privacy_tip_outlined, 'Privacy & terms', 'Privacy policy and terms of service', () => _info('Privacy & terms', 'The published privacy policy and terms will be available here.')),
        _item(context, Icons.delete_outline_rounded, 'Delete account', 'Request permanent account deletion', () => _info('Delete account', 'Account deletion will require identity verification and a secure backend workflow. Contact support until that workflow is enabled.')),
      ]),
    );
  }

  Widget _item(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) =>
    Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.35))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: const Color(0xFF176B57))),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );

  Future<void> _info(String title, String detail) async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: Text(detail),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
    ));
  }
}
