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
    await _info('Deletion not enabled yet', 'Account deletion is not available yet. No account data has been deleted.');
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
          _item(context, Icons.directions_car_filled_rounded, 'My rides', 'Ride history and trip details', () { Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerOrdersPage())); }),
          _item(context, Icons.location_on_outlined, 'Saved addresses', 'Home, work and other locations', () async {
            if (client?.auth.currentUser == null) { await _signIn(); if (!mounted || client?.auth.currentUser == null) return; }
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerAddressesPage()));
            if (mounted) setState(() {});
          }),
          _item(context, Icons.payments_outlined, 'Payments', 'Cash on delivery available · More methods coming soon', () { Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerPaymentMethodsPage())); }),
          _item(context, Icons.settings_outlined, 'Settings', 'Theme, language and account preferences', () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerSettingsPage(onTheme: _chooseTheme, onLanguage: _chooseLanguage, onDelete: _confirmDeleteAccount)));
          }),
          _item(context, Icons.support_agent_rounded, 'Help & support', 'Send a request and check its status', () async { if (client?.auth.currentUser == null) { await _signIn(); if (!mounted || client?.auth.currentUser == null) return; } await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerSupportPage())); }),
          _item(context, Icons.privacy_tip_outlined, 'Privacy policy', 'How Alteo handles your information', () => _showPrivacyPolicy()),
          _item(context, Icons.info_outline_rounded, 'About app', 'What Alteo is built for', () { Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerAboutPage())); }),
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
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerPrivacyPolicyPage()));
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


class CustomerPaymentMethodsPage extends StatelessWidget {
  const CustomerPaymentMethodsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payments')),
    body: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(20)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.payments_rounded, color: Color(0xFF176B57), size: 30),
          SizedBox(height: 10),
          Text('Choose how you pay', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          SizedBox(height: 5),
          Text('Cash on delivery is available at checkout for eligible orders. Other payment methods will be enabled in a future update.', style: TextStyle(height: 1.45)),
        ]),
      ),
      const SizedBox(height: 16),
      const _PaymentOption(icon: Icons.payments_outlined, title: 'Cash on delivery', subtitle: 'Pay in cash when your order arrives', available: true),
      const _PaymentOption(icon: Icons.account_balance_rounded, title: 'UPI', subtitle: 'Coming soon', available: false),
      const _PaymentOption(icon: Icons.credit_card_rounded, title: 'Credit and debit cards', subtitle: 'Not available yet', available: false),
      const _PaymentOption(icon: Icons.account_balance_wallet_outlined, title: 'Wallets', subtitle: 'Not available yet', available: false),
      const _PaymentOption(icon: Icons.account_balance_outlined, title: 'Net banking', subtitle: 'Not available yet', available: false),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerOrdersPage())),
        icon: const Icon(Icons.receipt_long_rounded), label: const Text('View your orders'),
      ),
    ]),
  );
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({required this.icon, required this.title, required this.subtitle, required this.available});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool available;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0, margin: const EdgeInsets.only(bottom: 9),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: available ? const Color(0xFFB9DFCD) : Theme.of(context).dividerColor.withOpacity(.45))),
    child: ListTile(
      leading: CircleAvatar(backgroundColor: available ? const Color(0xFFE1F2E9) : const Color(0xFFF0F2F0), child: Icon(icon, color: available ? const Color(0xFF176B57) : const Color(0xFF8B938E))),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: available ? null : const Color(0xFF747D77))),
      subtitle: Text(subtitle),
      trailing: available ? const Icon(Icons.check_circle_rounded, color: Color(0xFF176B57)) : const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF969E98)),
    ),
  );
}

class CustomerSupportPage extends StatefulWidget {
  const CustomerSupportPage({super.key});
  @override
  State<CustomerSupportPage> createState() => _CustomerSupportPageState();
}

class _CustomerSupportPageState extends State<CustomerSupportPage> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _submitting = false;
  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() { _subject.dispose(); _message.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to send a support request.')));
      return;
    }
    if (_subject.text.trim().length < 4 || _message.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a short subject and explain the issue in at least 10 characters.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await _client.from('support_tickets').insert({
        'requester_id': user.id, 'subject': _subject.text.trim(), 'message': _message.text.trim(),
      }).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      _subject.clear(); _message.clear(); FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your support request has been sent. You can follow its status below.')));
      setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not send your request. Check your connection and try again.')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(18)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.support_agent_rounded, color: Color(0xFF176B57), size: 30), SizedBox(width: 12),
            Expanded(child: Text('Tell us what went wrong. Your request is saved to your account so you can return to check its status.', style: TextStyle(height: 1.45))),
          ]),
        ),
        const SizedBox(height: 16),
        TextField(controller: _subject, maxLength: 120, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Subject', hintText: 'For example, an order or payment issue', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _message, minLines: 4, maxLines: 8, maxLength: 3000, decoration: const InputDecoration(labelText: 'How can we help?', hintText: 'Describe the issue and include any useful order details.', alignLabelWithHint: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _submitting || user == null ? null : _submit,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
          label: Text(_submitting ? 'Sending request…' : 'Send support request'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
        if (user == null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Sign in to send and view support requests.', style: TextStyle(color: Color(0xFF68736D)))),
        const SizedBox(height: 26),
        const Text('Your requests', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        if (user == null)
          const Text('Sign in to see requests linked to your account.')
        else
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _client.from('support_tickets').stream(primaryKey: ['id']).eq('requester_id', user.id).order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('Your request history could not be loaded right now.');
              if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()));
              if (snapshot.data!.isEmpty) return const Text('You have not sent a support request yet.');
              return Column(children: snapshot.data!.map((ticket) {
                final created = DateTime.tryParse(ticket['created_at']?.toString() ?? '');
                final date = created == null ? '' : created.day.toString().padLeft(2, '0') + '/' + created.month.toString().padLeft(2, '0') + '/' + created.year.toString();
                final status = ticket['status']?.toString() ?? 'open';
                final detail = (ticket['message']?.toString() ?? '') + '\\n' + date;
                return Card(
                  elevation: 0, margin: const EdgeInsets.only(bottom: 9),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFFE1F2E9), child: Icon(Icons.confirmation_number_outlined, color: Color(0xFF176B57))),
                    title: Text(ticket['subject']?.toString() ?? 'Support request', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
                    isThreeLine: true, trailing: _StatusPill(status: status),
                  ),
                );
              }).toList());
            },
          ),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: status == 'resolved' || status == 'closed' ? const Color(0xFFDDF3E6) : const Color(0xFFFFF0D8), borderRadius: BorderRadius.circular(20)),
    child: Text(status.replaceAll('_', ' '), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
  );
}

class CustomerPrivacyPolicyPage extends StatelessWidget {
  const CustomerPrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy policy')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: const [
      Text('Your privacy matters', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      SizedBox(height: 8),
      Text('This policy explains how Alteo uses information to support shopping, delivery and rides. Last updated: 27 October 2026.', style: TextStyle(height: 1.5, color: Color(0xFF68736D))),
      SizedBox(height: 22),
      _PolicySection(title: '1. Information you provide', body: 'When you sign in, we receive basic account details made available by your sign-in provider, such as your name and email address. You may also provide recipient names, phone numbers, delivery addresses, saved locations, cart contents, order details, ride requests and support messages.'),
      _PolicySection(title: '2. Location information', body: 'Alteo uses your device location when you choose a location feature and grant permission. Your location can help set a pickup or delivery point and calculate a route. Driver and delivery partners may share their current location while they are online and completing assigned work so customers can follow an active trip or delivery. You can deny location permission and enter an address manually.'),
      _PolicySection(title: '3. How information is used', body: 'We use this information to sign you in, show available items and services, save your preferences, calculate delivery or ride details, create and fulfil orders, provide status updates, protect accounts and respond to support requests.'),
      _PolicySection(title: '4. When information is shared', body: 'Information is shared only as needed to operate the service. For example, a seller receives details needed to prepare an order, and an assigned driver or delivery partner receives details needed to complete a ride or delivery. Service providers may process the information needed to host the app, protect accounts, display maps or send service notifications. Alteo does not sell your personal information.'),
      _PolicySection(title: '5. Storage and protection', body: 'We use account permissions and access controls designed to limit who can view customer, order, location and support information. Do not share one-time sign-in codes or account access with another person.'),
      _PolicySection(title: '6. Retention and deletion', body: 'We keep information for as long as needed to operate your account and services, respond to disputes, maintain safety and meet applicable record-keeping requirements. You can request account deletion from Settings. Some order records may need to be retained where required or to resolve a dispute.'),
      _PolicySection(title: '7. Your choices', body: 'You can update saved addresses, choose whether to grant location permission, change app preferences and submit a privacy question through Help & support. You can also request account deletion from Settings.'),
      _PolicySection(title: '8. Questions', body: 'For questions about your information, use Help & support in the Alteo app. Please do not include passwords or sign-in codes in a support message.'),
    ]),
  );
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6), Text(body, style: const TextStyle(height: 1.55, fontSize: 14)),
    ]),
  );
}

class CustomerAboutPage extends StatelessWidget {
  const CustomerAboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About Alteo')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 28), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF2C8B70)]), borderRadius: BorderRadius.circular(24)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 30, backgroundColor: Color(0x33FFFFFF), child: Text('A', style: TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.w900))),
          SizedBox(height: 14),
          Text('Everyday, made easier.', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text('Alteo brings everyday shopping and local mobility together in one place.', style: TextStyle(color: Colors.white, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 22),
      const _AboutFeature(icon: Icons.shopping_bag_outlined, title: 'Shop essentials', detail: 'Discover products listed by marketplace partners.'),
      const _AboutFeature(icon: Icons.restaurant_outlined, title: 'Explore food and quick commerce', detail: 'Browse available categories and offers in your service area.'),
      const _AboutFeature(icon: Icons.directions_car_outlined, title: 'Book rides', detail: 'Set a pickup and destination and view an estimated fare when available.'),
      const _AboutFeature(icon: Icons.local_shipping_outlined, title: 'Follow orders and deliveries', detail: 'See order status and tracking details when a partner has been assigned.'),
      const SizedBox(height: 12),
      const Text('Availability depends on your location and current service setup. Payment options and map features are being introduced in stages.', style: TextStyle(color: Color(0xFF68736D), height: 1.5)),
      const SizedBox(height: 18),
      const Center(child: Text('Alteo · Version 0.1.0', style: TextStyle(fontWeight: FontWeight.w800))),
    ]),
  );
}

class _AboutFeature extends StatelessWidget {
  const _AboutFeature({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title, detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: const Color(0xFF176B57))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 4), Text(detail, style: const TextStyle(height: 1.45, color: Color(0xFF68736D))),
      ])),
    ]),
  );
}
