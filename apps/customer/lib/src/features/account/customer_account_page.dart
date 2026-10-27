import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alteo_notifications/alteo_notifications.dart';
import '../../services/customer_preferences.dart';
import '../auth/customer_auth_page.dart';
import '../orders/customer_orders_page.dart';
import '../addresses/customer_addresses_page.dart';

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
      builder: (sheetContext) => ValueListenableBuilder<ThemeMode>(
        valueListenable: alteoThemeMode,
        builder: (context, mode, _) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: Text(alteoText('Theme'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            const SizedBox(height: 12),
            for (final option in <(String, ThemeMode, IconData)>[
              ('Light', ThemeMode.light, Icons.light_mode_outlined),
              ('Dark', ThemeMode.dark, Icons.dark_mode_outlined),
              ('Follow device', ThemeMode.system, Icons.settings_brightness_outlined),
            ])
              RadioListTile<ThemeMode>(
                value: option.$2, groupValue: mode, title: Text(alteoText(option.$1)), secondary: Icon(option.$3),
                onChanged: (value) async { if (value != null) await setAlteoTheme(value); },
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
      builder: (sheetContext) => ValueListenableBuilder<String>(
        valueListenable: alteoPreferredLanguage,
        builder: (context, language, _) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: Text(alteoText('Language'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            const SizedBox(height: 12),
            for (final option in languages)
              RadioListTile<String>(
                value: option, groupValue: language, title: Text(option),
                onChanged: (value) async {
                  if (value != null) {
                    await setAlteoLanguage(value);
                    if (mounted) setState(() {});
                  }
                },
              ),
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Your choice is saved on this device. Translations are being expanded across the app.', style: TextStyle(fontSize: 12, color: Color(0xFF68736D)))),
          ]),
        )),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded, color: Color(0xFFB3261E), size: 32),
        title: Text(alteoText('Confirm logout?')),
        content: Text(alteoText('Are you sure you want to log out of your Alteo account?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(alteoText('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(alteoText('Logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await AlteoPushNotifications.instance.unregisterCurrentDevice();
      await client?.auth.signOut();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not log out completely. Please try again.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final user = client?.auth.currentUser;
    if (user == null) {
      await _info(alteoText('Delete account'), 'Sign in first to manage your account.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined, color: Color(0xFFB3261E), size: 34),
        title: Text(alteoText('Confirm deletion?')),
        content: const Text('Account deletion is permanent and may remove your profile and associated data. You will need to verify your identity. Continue only if you are sure.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(alteoText('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Auth-user deletion must be performed by a privileged server-side workflow.
    // Do not attempt to delete the auth user directly from the client.
    await _info('Deletion not enabled yet', 'Your confirmation was received, but secure account deletion is not enabled on the backend yet. No account data has been deleted.');
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: alteoPreferredLanguage,
    builder: (context, language, _) {
      final user = client?.auth.currentUser;
      return Scaffold(
        appBar: AppBar(title: Text(alteoText('Profile')), centerTitle: false),
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
          if (user == null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _signIn, icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in with Google'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF176B57), minimumSize: const Size.fromHeight(52)),
            ),
          ],
          const SizedBox(height: 18),
          _item(context, Icons.receipt_long_rounded, 'My orders', 'Shopping, food and parcel orders', () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerOrdersPage()));
          }),
          _item(context, Icons.directions_car_filled_rounded, 'My rides', 'Ride history and trip details', () => _info(alteoText('My rides'), 'Your completed and active rides will appear here when ride history is available.')),
          _item(context, Icons.location_on_outlined, 'Saved addresses', 'Home, work and other locations', () async {
            if (client?.auth.currentUser == null) { await _signIn(); if (!mounted || client?.auth.currentUser == null) return; }
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerAddressesPage()));
            if (mounted) setState(() {});
          }),
          _item(context, Icons.payments_outlined, 'Payments', 'Payment methods and transactions', () => _info(alteoText('Payments'), 'Payment methods and transactions will be available here as payment services are enabled.')),
          _item(context, Icons.settings_outlined, 'Settings', 'Theme, language and account preferences', () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerSettingsPage(onTheme: _chooseTheme, onLanguage: _chooseLanguage, onDelete: _confirmDeleteAccount)));
          }),
          _item(context, Icons.support_agent_rounded, 'Help & support', 'Get help with Alteo services', () => _info('Help & support', 'Support contact details will be published before public launch.')),
          _item(context, Icons.privacy_tip_outlined, 'Privacy policy', 'How Alteo handles your information', () => _showPrivacyPolicy()),
          _item(context, Icons.info_outline_rounded, 'About app', 'Alteo • Version 0.1.0', () => _info('About Alteo', 'Alteo brings shopping, food, everyday essentials and rides together in one app. Version 0.1.0.')),
          if (user != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : _confirmLogout,
              icon: const Icon(Icons.logout_rounded),
              label: Text(busy ? 'Logging out…' : alteoText('Logout')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: const Color(0xFFB3261E), side: const BorderSide(color: Color(0xFFB3261E))),
            ),
          ],
        ]),
      );
    },
  );

  Future<void> _showPrivacyPolicy() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(alteoText('Privacy policy')),
        content: const SingleChildScrollView(child: Text('Alteo uses account information to provide sign-in, saved addresses, orders, rides and related services. Information should only be used for service operation, security and support. Before public launch, this summary must be replaced or supplemented with the complete published privacy policy, including data retention, sharing, user rights and contact details.')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
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
        title: Text(alteoText(title), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );

  Future<void> _info(String title, String detail) async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: Text(detail),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(alteoText('Got it')))],
    ));
  }
}

class CustomerSettingsPage extends StatelessWidget {
  const CustomerSettingsPage({super.key, required this.onTheme, required this.onLanguage, required this.onDelete});
  final Future<void> Function() onTheme;
  final Future<void> Function() onLanguage;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: alteoPreferredLanguage,
    builder: (context, language, _) => Scaffold(
      appBar: AppBar(title: Text(alteoText('Settings'))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        _setting(context, Icons.palette_outlined, 'Theme', alteoThemeMode.value == ThemeMode.dark ? 'Dark' : alteoThemeMode.value == ThemeMode.system ? 'Follow device' : 'Light', onTheme),
        _setting(context, Icons.language_rounded, 'Language', language, onLanguage),
        _setting(context, Icons.delete_outline_rounded, 'Delete account', 'Request permanent account deletion', onDelete, danger: true),
      ]),
    ),
  );

  Widget _setting(BuildContext context, IconData icon, String title, String subtitle, Future<void> Function() onTap, {bool danger = false}) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.35))),
    child: ListTile(
      minVerticalPadding: 12,
      leading: CircleAvatar(backgroundColor: danger ? const Color(0xFFFFE8E6) : const Color(0xFFE1F2E9), child: Icon(icon, color: danger ? const Color(0xFFB3261E) : const Color(0xFF176B57))),
      title: Text(alteoText(title), style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(title == 'Theme' ? alteoText(subtitle) : subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => onTap(),
    ),
  );
}
