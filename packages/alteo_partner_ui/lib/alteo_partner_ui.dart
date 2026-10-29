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
        _item('Service availability and changes', 'Work availability depends on approval, service-area coverage, stock and dispatch readiness. Showing an option does not override account eligibility or safety checks.'),
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


class AlteoPartnerAccountCard extends StatefulWidget {
  const AlteoPartnerAccountCard({super.key, required this.role, required this.userId});
  final String role;
  final String userId;
  @override
  State<AlteoPartnerAccountCard> createState() => _AlteoPartnerAccountCardState();
}

class _AlteoPartnerAccountCardState extends State<AlteoPartnerAccountCard> {
  late Future<Map<String, dynamic>?> _request = _load();
  Future<Map<String, dynamic>?> _load() async {
    final rows = await Supabase.instance.client.from('role_requests')
      .select('requested_role,status,display_name,email,phone,application_data,rejection_reason,needs_correction,correction_reason')
      .eq('user_id', widget.userId).eq('requested_role', widget.role)
      .order('requested_at', ascending: false).limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: _request,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Card(elevation: 0, child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
      }
      if (snapshot.hasError) return Card(elevation: 0, child: ListTile(
        title: const Text('Partner account'),
        subtitle: const Text('Account details could not be loaded.'),
        trailing: IconButton(onPressed: () => setState(() => _request = _load()), icon: const Icon(Icons.refresh_rounded)),
      ));
      final row = snapshot.data;
      final raw = row?['application_data'];
      final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final status = (row?['status'] ?? 'not submitted').toString();
      final statusColor = status == 'approved' ? _green : status == 'rejected' ? const Color(0xFFB3261E) : const Color(0xFF8A5A00);
      final details = <MapEntry<String, Object?>>[
        MapEntry('Mobile', row?['phone']),
        if (widget.role == 'seller') MapEntry('Business', data['shop_name']),
        if (widget.role == 'seller') MapEntry('Category', data['business_category']),
        if (widget.role == 'dark_store') MapEntry('Store', data['store_name']),
        if (widget.role == 'dark_store') MapEntry('Operating hours', data['operating_hours']),
        if (widget.role == 'driver_partner' || widget.role == 'delivery_partner') MapEntry('Vehicle', data['vehicle_type']),
        if (widget.role == 'driver_partner' || widget.role == 'delivery_partner') MapEntry('Registration', data['vehicle_registration']),
        if (widget.role == 'driver_partner') MapEntry('Licence no.', data['driving_licence_number']),
        if (widget.role == 'driver_partner' || widget.role == 'delivery_partner') MapEntry('Service PIN', data['service_area']),
        MapEntry('Address', data['address']),
      ];
      return Card(elevation: 0, margin: const EdgeInsets.only(top: 12, bottom: 6),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(backgroundColor: _paleGreen, child: Icon(Icons.verified_user_outlined, color: _green)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((row?['display_name'] ?? Supabase.instance.client.auth.currentUser?.email ?? 'Partner').toString(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text(widget.role.replaceAll('_', ' '), style: const TextStyle(color: Color(0xFF68736D))),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(18)),
                child: Text(status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor))),
            ]),
            const SizedBox(height: 14),
            for (final detail in details)
              if (detail.value != null && detail.value.toString().trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 112, child: Text(detail.key, style: const TextStyle(color: Color(0xFF68736D), fontSize: 12))),
                  Expanded(child: Text(detail.value.toString(), style: const TextStyle(fontWeight: FontWeight.w700))),
                ])),
            if (row?['needs_correction'] == true) ...[
              const Divider(height: 20),
              const Text('Action required', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF8A5A00))),
              Text((row?['correction_reason'] ?? 'Admin requested corrections to your application.').toString(), style: const TextStyle(height: 1.4)),
            ] else if (status == 'rejected' && (row?['rejection_reason']?.toString().isNotEmpty ?? false)) ...[
              const Divider(height: 20),
              const Text('Admin feedback', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFB3261E))),
              Text(row!['rejection_reason'].toString(), style: const TextStyle(height: 1.4)),
            ],
          ],
        )),
      );
    },
  );
}

class AlteoPartnerRatingCard extends StatefulWidget {
  const AlteoPartnerRatingCard({super.key, required this.role, required this.userId});
  final String role;
  final String userId;
  @override
  State<AlteoPartnerRatingCard> createState() => _AlteoPartnerRatingCardState();
}

class _AlteoPartnerRatingCardState extends State<AlteoPartnerRatingCard> {
  late Future<Map<String, dynamic>> _summary = _load();
  Future<Map<String, dynamic>> _load() async {
    final client = Supabase.instance.client;
    var subjectId = widget.userId;
    if (widget.role == 'seller') {
      final row = await client.from('sellers').select('id').eq('owner_id', widget.userId).limit(1).maybeSingle();
      subjectId = row?['id']?.toString() ?? '';
    } else if (widget.role == 'dark_store') {
      final row = await client.from('dark_stores').select('id').eq('owner_user_id', widget.userId).limit(1).maybeSingle();
      subjectId = row?['id']?.toString() ?? '';
    }
    if (subjectId.isEmpty) return {'count': 0, 'average': 0.0, 'recent': <Map<String, dynamic>>[]};
    final rows = await client.from('service_ratings').select('id,score,comment,reviewer_role,created_at')
      .eq('subject_role', widget.role).eq('subject_id', subjectId).eq('status', 'published')
      .order('created_at', ascending: false).limit(30);
    final recent = List<Map<String, dynamic>>.from(rows as List);
    final sum = recent.fold<double>(0, (total, row) => total + ((row['score'] as num?)?.toDouble() ?? 0));
    return {'count': recent.length, 'average': recent.isEmpty ? 0.0 : sum / recent.length, 'recent': recent.take(3).toList()};
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _summary,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Card(elevation: 0, child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
      if (snapshot.hasError) return Card(elevation: 0, child: ListTile(
        leading: const Icon(Icons.star_outline_rounded, color: Color(0xFF8A5A00)),
        title: const Text('Ratings & feedback'), subtitle: const Text('Ratings could not be loaded.'),
        trailing: IconButton(onPressed: () => setState(() => _summary = _load()), icon: const Icon(Icons.refresh_rounded)),
      ));
      final data = snapshot.data!;
      final count = data['count'] as int? ?? 0;
      final average = (data['average'] as num?)?.toDouble() ?? 0;
      final recent = List<Map<String, dynamic>>.from(data['recent'] as List);
      return Card(elevation: 0, margin: const EdgeInsets.only(top: 6, bottom: 8),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ratings & feedback', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.star_rounded, color: Color(0xFFE0A020), size: 30), const SizedBox(width: 6),
            Text(count == 0 ? 'No ratings yet' : average.toStringAsFixed(1), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
            if (count > 0) Expanded(child: Padding(padding: const EdgeInsets.only(left: 8),
              child: Text(count.toString() + ' published ratings', style: const TextStyle(color: Color(0xFF68736D))))),
          ]),
          if (count == 0) const Padding(padding: EdgeInsets.only(top: 5),
            child: Text('Ratings appear after eligible work is reviewed.', style: TextStyle(color: Color(0xFF68736D), height: 1.4))),
          for (final review in recent) ...[
            const Divider(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((review['score'] ?? 0).toString() + ' ★', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF8A5A00))),
              const SizedBox(width: 10),
              Expanded(child: Text((review['comment']?.toString().trim().isNotEmpty ?? false)
                ? review['comment'].toString() : 'No written feedback.', style: const TextStyle(height: 1.4))),
            ]),
          ],
        ])),
      );
    },
  );
}

class AlteoServiceAreaLocationCard extends StatelessWidget {
  const AlteoServiceAreaLocationCard({
    super.key, required this.role, required this.selectedPin, required this.activeAreas,
    required this.isOnline, required this.locationSummary, required this.isRefreshingLocation,
    required this.onAreaChanged, required this.onRefreshLocation, required this.onToggleAvailability,
    required this.onOpenMap,
  });
  final String role;
  final String? selectedPin;
  final List<Map<String, dynamic>> activeAreas;
  final bool isOnline;
  final String locationSummary;
  final bool isRefreshingLocation;
  final ValueChanged<String?> onAreaChanged;
  final VoidCallback onRefreshLocation;
  final VoidCallback onToggleAvailability;
  final VoidCallback onOpenMap;

  String _areaLabel(Map<String, dynamic> area) {
    final code = area['pincode']?.toString() ?? '';
    final locality = area['locality']?.toString().trim() ?? '';
    final district = area['district']?.toString().trim() ?? '';
    final label = <String>[if (locality.isNotEmpty) locality, if (district.isNotEmpty) district].join(' · ');
    return label.isEmpty ? code : code + ' · ' + label;
  }
  @override
  Widget build(BuildContext context) {
    final validPin = selectedPin != null && activeAreas.any((row) => row['pincode']?.toString() == selectedPin);
    return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFDCE6DF))),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(backgroundColor: _paleGreen, child: Icon(Icons.location_on_rounded, color: _green)), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Service area & live location', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text(isOnline ? 'Online · eligible for assignments' : 'Offline · not receiving new work',
              style: TextStyle(fontSize: 12, color: isOnline ? _green : const Color(0xFF68736D))),
          ])),
          Icon(isOnline ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded, color: isOnline ? _green : const Color(0xFF68736D)),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: validPin ? selectedPin : null, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Active service PIN code *', border: OutlineInputBorder(), helperText: 'Choose where you want to receive work.'),
          items: activeAreas.map((area) => DropdownMenuItem<String>(
            value: area['pincode']?.toString(), child: Text(_areaLabel(area), maxLines: 2, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: activeAreas.isEmpty ? null : onAreaChanged,
        ),
        if (activeAreas.isEmpty) const Padding(padding: EdgeInsets.only(top: 5),
          child: Text('No active PIN codes are configured. Contact Alteo Admin.', style: TextStyle(color: Color(0xFFB3261E), height: 1.4))),
        const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF5F7F5), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(isRefreshingLocation ? Icons.gps_not_fixed_rounded : Icons.my_location_rounded, color: _green),
            const SizedBox(width: 10), Expanded(child: Text(locationSummary, style: const TextStyle(height: 1.4))),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: isRefreshingLocation ? null : onRefreshLocation,
            icon: isRefreshingLocation ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded),
            label: Text(isRefreshingLocation ? 'Updating location…' : 'Refresh location')),
          OutlinedButton.icon(onPressed: onOpenMap, icon: const Icon(Icons.map_outlined), label: const Text('Open map')),
          FilledButton.icon(onPressed: validPin && !isRefreshingLocation ? onToggleAvailability : null,
            icon: Icon(isOnline ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded),
            label: Text(isOnline ? 'Go offline' : 'Go online'),
            style: FilledButton.styleFrom(backgroundColor: isOnline ? const Color(0xFF5C6861) : _green)),
        ]),
      ])),
    );
  }
}

class AlteoRateCompletedWorkButton extends StatefulWidget {
  const AlteoRateCompletedWorkButton({
    super.key, required this.role, required this.transactionType, required this.transactionId, this.onSubmitted,
  });
  final String role;
  final String transactionType;
  final String transactionId;
  final VoidCallback? onSubmitted;
  @override
  State<AlteoRateCompletedWorkButton> createState() => _AlteoRateCompletedWorkButtonState();
}

class _AlteoRateCompletedWorkButtonState extends State<AlteoRateCompletedWorkButton> {
  bool _busy = false;
  Future<void> _rate() async {
    var score = 5;
    final comment = TextEditingController();
    try {
      final chosen = await showDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate completed work'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Rate your experience from 1 to 5 stars. Keep feedback factual and respectful.', style: TextStyle(height: 1.4)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var value = 1; value <= 5; value++)
                IconButton(tooltip: value.toString() + ' stars', onPressed: () => setDialogState(() => score = value),
                  icon: Icon(value <= score ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFE0A020), size: 30)),
            ]),
            TextField(controller: comment, maxLength: 500, maxLines: 3,
              decoration: const InputDecoration(labelText: 'Optional comment', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, score), child: const Text('Submit rating')),
          ],
        )),
      );
      if (chosen == null || !mounted) return;
      setState(() => _busy = true);
      await Supabase.instance.client.rpc('submit_service_rating', params: {
        'p_transaction_type': widget.transactionType, 'p_transaction_id': widget.transactionId,
        'p_reviewer_role': widget.role, 'p_score': chosen,
        'p_comment': comment.text.trim().isEmpty ? null : comment.text.trim(),
      }).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rating submitted. Thank you for your feedback.')));
      widget.onSubmitted?.call();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase().contains('already rated')
        ? 'You have already rated this work item.'
        : 'Rating could not be submitted. Make sure the work is complete and belongs to your account.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      comment.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _busy ? null : _rate,
    icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.star_outline_rounded),
    label: Text(_busy ? 'Submitting…' : 'Rate completed work'),
  );
}


class AlteoPartnerPublicProfileCard extends StatelessWidget {
  const AlteoPartnerPublicProfileCard({super.key, required this.appName, required this.role});
  final String appName;
  final String role;

  @override
  Widget build(BuildContext context) {
    final icon = switch (role) {
      'driver_partner' => Icons.directions_car_filled_rounded,
      'delivery_partner' => Icons.local_shipping_rounded,
      'seller' => Icons.storefront_rounded,
      'dark_store' => Icons.warehouse_rounded,
      _ => Icons.admin_panel_settings_rounded,
    };
    final description = switch (role) {
      'driver_partner' => 'Manage your vehicle and verification status, service PIN, current location, rides, earnings and completed-work ratings.',
      'delivery_partner' => 'Manage your vehicle, service PIN, current location, assigned deliveries, delivery earnings and completed-work ratings.',
      'seller' => 'Manage your business details, approval status, products, inventory, orders and customer feedback.',
      'dark_store' => 'Manage your store details, activation status, inventory, picking and handover performance.',
      _ => 'Manage your Alteo account, authorisations, service areas, partners and platform operations.',
    };
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDCE6DF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: _paleGreen,
              child: Icon(icon, size: 27, color: _green),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(height: 1.45)),
                const SizedBox(height: 10),
                const Row(children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: _green),
                  SizedBox(width: 5),
                  Expanded(child: Text('Sign in to view your account and approval status.',
                    style: TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w700))),
                ]),
              ],
            )),
          ],
        ),
      ),
    );
  }
}
