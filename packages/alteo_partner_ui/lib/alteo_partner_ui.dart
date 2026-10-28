import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _green = Color(0xFF176B57);
const _paleGreen = Color(0xFFE1F2E9);

/// Preferences are stored per app so the same device can keep different
/// settings for Seller, Driver, Delivery, Dark Store and Admin.
Future<void> loadAlteoPartnerPreferences({
  required String appId,
  required ValueNotifier<ThemeMode> themeMode,
  required ValueNotifier<String> language,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString('alteo_partner_theme_$appId') ?? 'light';
    themeMode.value = switch (theme) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    final preferred = prefs.getString('alteo_partner_language_$appId') ?? 'English';
    language.value = const ['English', 'हिन्दी', 'বাংলা', 'தமிழ்'].contains(preferred)
        ? preferred
        : 'English';
  } catch (error) {
    debugPrint('Could not load Alteo appearance preferences (${error.runtimeType}).');
  }
}

Future<void> saveAlteoPartnerTheme(String appId, ThemeMode mode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alteo_partner_theme_$appId', switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      _ => 'light',
    });
  } catch (error) {
    debugPrint('Could not save Alteo theme preference (${error.runtimeType}).');
  }
}

Future<void> saveAlteoPartnerLanguage(String appId, String language) async {
  if (!const ['English', 'हिन्दी', 'বাংলা', 'தமிழ்'].contains(language)) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alteo_partner_language_$appId', language);
  } catch (error) {
    debugPrint('Could not save Alteo language preference (${error.runtimeType}).');
  }
}

Future<void> confirmAlteoLogout(
  BuildContext context, {
  required Future<void> Function() onConfirm,
}) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.logout_rounded),
      title: const Text('Log out of Alteo?'),
      content: const Text('You will need to sign in again to access your protected workspace. Any saved work on the server will remain available to your account.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (shouldLogout == true) await onConfirm();
}

class AlteoAboutPage extends StatelessWidget {
  const AlteoAboutPage({
    super.key,
    required this.appName,
    required this.role,
    this.version = '0.1.0',
  });

  final String appName;
  final String role;
  final String version;

  String get _description => switch (role) {
    'admin' => 'The owner and operations workspace for service availability, partners, catalogue, orders and customer support.',
    'seller' => 'The seller workspace for maintaining approved listings, inventory and the orders routed to your store.',
    'driver_partner' => 'The driver workspace for availability, assigned rides, navigation and trip updates.',
    'delivery_partner' => 'The delivery workspace for assigned jobs, pickup, navigation, delivery status and proof of delivery.',
    'dark_store' => 'The fulfilment workspace for inventory, order picking, packing and dispatch handover.',
    _ => 'An operational workspace for the Alteo marketplace.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About this app')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF2C8B70)]),
              borderRadius: BorderRadius.circular(25),
            ),
            alignment: Alignment.center,
            child: const Text('A', style: TextStyle(fontSize: 54, height: 1, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 16),
        Text(appName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Version $version', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 22),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(_description, style: const TextStyle(fontSize: 15, height: 1.55)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Built for reliable local commerce and fulfilment. Features are available according to your account role, approval status and service configuration.', style: TextStyle(height: 1.5)),
      ],
    ),
  );
}

class AlteoPrivacyPage extends StatelessWidget {
  const AlteoPrivacyPage({super.key, required this.appName});
  final String appName;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy information')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(appName, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('This page explains the main ways Alteo operational apps use account and work-related information.', style: TextStyle(height: 1.5)),
        const SizedBox(height: 18),
        _section('Information used', 'Account details, partner or business profile information, documents you choose to submit, assigned work, status updates and support messages.'),
        _section('Location', 'Location access is used for location-dependent work such as availability, nearby assignments, pickup or delivery navigation. Live location should be shared only when the relevant workflow and permission allow it. You can change app permissions in Android Settings.'),
        _section('Notifications', 'If notifications are permitted and configured, the app may use a device registration to deliver relevant assignment, order or account updates. Permission does not guarantee a notification will be delivered.'),
        _section('How information is used', 'Information supports sign-in, partner approval, work assignment, fulfilment, customer communication, service safety, issue resolution and platform security.'),
        _section('Who can see it', 'Information should be available only to the account holder and authorised Alteo staff or service participants who need it to complete the relevant operation. The app should not expose another partner’s private records.'),
        _section('Storage and retention', 'Operational records may need to be retained for service, dispute, security or legal reasons. Access is controlled by account permissions. Do not upload documents or personal details that are not required for your role.'),
        _section('Your choices', 'Keep your profile information accurate. You can change device permissions in Android Settings and use Help & support in this app to request account or data assistance.'),
        const SizedBox(height: 12),
        const Text('This in-app notice describes the current operational use of information. Before public launch, Alteo should publish a complete, legally reviewed privacy policy with the responsible business entity, data-retention schedule and contact details.', style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF68736D))),
      ],
    ),
  );

  Widget _section(String title, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      Text(detail, style: const TextStyle(height: 1.5)),
    ]),
  );
}

class AlteoTermsPage extends StatelessWidget {
  const AlteoTermsPage({super.key, required this.appName, required this.role});
  final String appName;
  final String role;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Terms of use')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(appName, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Operational terms for people using Alteo partner and administration tools.', style: TextStyle(height: 1.5)),
        const SizedBox(height: 18),
        _item('Use your own approved account', 'Do not share credentials, impersonate another person, or attempt to access records outside your assigned role.'),
        _item('Keep information accurate', 'Maintain accurate profile and business details. Submit genuine documents and correct listing, inventory or fulfilment information.'),
        _item('Follow the assigned workflow', 'Use the app only for work you are authorised to perform. Update ride, delivery, stock and order statuses accurately, and do not mark work complete before it is complete.'),
        _item('Use location responsibly', 'When location is needed for availability or an active assignment, use it only for that work and follow the relevant safety and privacy requirements.'),
        _item('Protect customers and partners', 'Use customer, seller, order and location information only to complete the permitted operation. Do not copy, disclose or misuse it.'),
        _item('Service availability and changes', 'Work availability depends on approval, service-area coverage, stock, dispatch and platform configuration. A screen showing an option does not override backend eligibility or safety checks.'),
        _item('Issues and violations', 'Report incorrect assignments, suspected abuse, safety concerns or technical problems through Help & support. Alteo may restrict access when security, fraud or policy concerns require review.'),
        const SizedBox(height: 12),
        const Text('This is an operational terms summary, not a substitute for a complete legal agreement. A full version should be reviewed and published before public launch.', style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF68736D))),
      ],
    ),
  );

  Widget _item(String title, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      Text(detail, style: const TextStyle(height: 1.5)),
    ]),
  );
}

class AlteoHelpSupportPage extends StatefulWidget {
  const AlteoHelpSupportPage({super.key, required this.appName, required this.role});
  final String appName;
  final String role;

  @override
  State<AlteoHelpSupportPage> createState() => _AlteoHelpSupportPageState();
}

class _AlteoHelpSupportPageState extends State<AlteoHelpSupportPage> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _submitting = false;
  late Future<List<Map<String, dynamic>>> _tickets = _loadTickets();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadTickets() async {
    final user = _client.auth.currentUser;
    if (user == null) return <Map<String, dynamic>>[];
    final response = await _client
        .from('support_tickets')
        .select('id,subject,message,status,created_at,updated_at')
        .eq('requester_id', user.id)
        .order('created_at', ascending: false)
        .limit(20)
        .timeout(const Duration(seconds: 15));
    return (response as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> _submit() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _messageBar('Your session has ended. Sign in again to contact support.');
      return;
    }
    if (_subject.text.trim().length < 4 || _message.text.trim().length < 10) {
      _messageBar('Add a subject and describe the issue in at least 10 characters.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _client.from('support_tickets').insert({
        'requester_id': user.id,
        'subject': '[${widget.role}] ${_subject.text.trim()}',
        'message': _message.text.trim(),
      }).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      _subject.clear();
      _message.clear();
      setState(() => _tickets = _loadTickets());
      _messageBar('Your request has been sent. Its status will appear below.');
    } catch (error) {
      debugPrint('Alteo support ticket submission failed (${error.runtimeType}).');
      _messageBar('We could not send your request. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _messageBar(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help & support')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _paleGreen, borderRadius: BorderRadius.circular(18)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.support_agent_rounded, color: _green, size: 30),
            const SizedBox(width: 12),
            Expanded(child: Text('Contact Alteo support about your ${widget.role.replaceAll('_', ' ')} account, assigned work, access or a technical problem. Please do not include passwords or verification codes.', style: const TextStyle(height: 1.5))),
          ]),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _subject,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Subject', hintText: 'What do you need help with?', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _message,
          minLines: 4,
          maxLines: 8,
          maxLength: 3000,
          decoration: const InputDecoration(labelText: 'Describe the issue', hintText: 'Include relevant order or assignment details, but no sensitive credentials.', alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
          label: Text(_submitting ? 'Sending request…' : 'Send support request'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
        const SizedBox(height: 26),
        const Text('Your support requests', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _tickets,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return Card(elevation: 0, child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your request history is temporarily unavailable.'),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                    onPressed: () => setState(() => _tickets = _loadTickets()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  )),
                ]),
              ));
            }
            final tickets = snapshot.data ?? <Map<String, dynamic>>[];
            if (tickets.isEmpty) return const Card(elevation: 0, child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No support requests yet. Requests you send from this page will appear here.'),
            ));
            return Column(children: tickets.map((ticket) {
              final createdAt = DateTime.tryParse(ticket['created_at']?.toString() ?? '')?.toLocal();
              final dateLabel = createdAt == null ? '' : '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
              final status = (ticket['status']?.toString() ?? 'open').replaceAll('_', ' ');
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.35))),
                child: ListTile(
                  isThreeLine: true,
                  title: Text(ticket['subject']?.toString() ?? 'Support request', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${ticket['message']?.toString() ?? ''}\n$dateLabel', maxLines: 3, overflow: TextOverflow.ellipsis),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(color: status == 'resolved' ? _paleGreen : const Color(0xFFFFF2D8), borderRadius: BorderRadius.circular(10)),
                    child: Text(status, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              );
            }).toList());
          },
        ),
      ],
    ),
  );
}


class AlteoDevicePermissionsPage extends StatelessWidget {
  const AlteoDevicePermissionsPage({super.key, required this.appName, this.includeLocation = true});
  final String appName;
  final bool includeLocation;

  Future<void> _openSettings(BuildContext context) async {
    try {
      final opened = await Geolocator.openAppSettings();
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Android settings could not be opened. Open this app under Settings > Apps to change permissions.')));
      }
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open Android Settings > Apps > this app to change permissions.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App permissions')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        Text(appName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Manage the device permissions used by this app. If you previously denied a permission, Android settings are the reliable place to enable it again.', style: TextStyle(height: 1.5)),
        const SizedBox(height: 18),
        if (includeLocation)
          Card(elevation: 0, child: ListTile(
            leading: const CircleAvatar(backgroundColor: _paleGreen, child: Icon(Icons.location_on_rounded, color: _green)),
            title: const Text('Location access', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Used for location-dependent assignments, pickup/delivery navigation and availability when the workflow requires it.'),
            isThreeLine: true,
          )),
        Card(elevation: 0, child: ListTile(
          leading: const CircleAvatar(backgroundColor: _paleGreen, child: Icon(Icons.notifications_active_outlined, color: _green)),
          title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Allow relevant assignment, order, account and support alerts to appear on your phone. Delivery still depends on notification-service configuration.'),
          isThreeLine: true,
        )),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => _openSettings(context),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Open Android app settings'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ],
    ),
  );
}
