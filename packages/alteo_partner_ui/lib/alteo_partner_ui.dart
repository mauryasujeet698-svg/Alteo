import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
      .select('requested_role,status,display_name,email,phone,profile_photo_path,application_data,rejection_reason,needs_correction,correction_reason')
      .eq('user_id', widget.userId).eq('requested_role', widget.role)
      .order('requested_at', ascending: false).limit(1);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    final photoPath = row['profile_photo_path']?.toString();
    if (photoPath != null && photoPath.isNotEmpty) {
      try {
        row['profile_photo_url'] = await Supabase.instance.client.storage
          .from('partner-onboarding').createSignedUrl(photoPath, 300);
      } catch (_) {}
    }
    return row;
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
        MapEntry('Email', row?['email']),
        MapEntry('Mobile', row?['phone']),
        if (widget.role == 'seller') MapEntry('Business', data['shop_name']),
        if (widget.role == 'seller') MapEntry('Category', data['business_category']),
        if (widget.role == 'seller') MapEntry('GSTIN', data['gstin']),
        if (widget.role == 'dark_store') MapEntry('Store', data['store_name']),
        if (widget.role == 'dark_store') MapEntry('Operating hours', data['operating_hours']),
        if (widget.role == 'dark_store') MapEntry('Facility', data['facility_details']),
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
              CircleAvatar(
                radius: 25,
                backgroundColor: _paleGreen,
                backgroundImage: row?['profile_photo_url']?.toString().isNotEmpty == true
                    ? NetworkImage(row!['profile_photo_url'].toString()) : null,
                child: row?['profile_photo_url']?.toString().isNotEmpty == true
                    ? null : const Icon(Icons.verified_user_outlined, color: _green),
              ),
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
          FilledButton.icon(onPressed: (validPin || isOnline) && !isRefreshingLocation ? onToggleAvailability : null,
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


class AlteoPincodeCoverageSelector extends StatefulWidget {
  const AlteoPincodeCoverageSelector({
    super.key, required this.initialMode, required this.initialPincodes,
    required this.allowAllPincodes, required this.onChanged,
  });
  final String initialMode;
  final List<String> initialPincodes;
  final bool allowAllPincodes;
  final void Function(String mode, List<String> pincodes) onChanged;
  @override
  State<AlteoPincodeCoverageSelector> createState() => _AlteoPincodeCoverageSelectorState();
}

class _AlteoPincodeCoverageSelectorState extends State<AlteoPincodeCoverageSelector> {
  late String _mode = widget.allowAllPincodes && widget.initialMode == 'all' ? 'all' : 'specific';
  late Set<String> _selected = widget.initialPincodes.toSet();
  late Future<List<Map<String, dynamic>>> _areas = _loadAreas();

  Future<List<Map<String, dynamic>>> _loadAreas() async {
    final rows = await Supabase.instance.client.from('service_areas')
      .select('pincode,locality,district,state').eq('active', true).order('pincode');
    return List<Map<String, dynamic>>.from(rows as List);
  }
  void _emit() {
    final pins = _mode == 'all' ? <String>[] : (_selected.toList()..sort());
    widget.onChanged(_mode, pins);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _areas,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator());
      }
      if (snapshot.hasError) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Service PIN codes could not be loaded. Check your connection and retry.'),
        TextButton.icon(onPressed: () => setState(() => _areas = _loadAreas()),
          icon: const Icon(Icons.refresh_rounded), label: const Text('Retry PIN list')),
      ]);
      final areas = snapshot.data ?? <Map<String, dynamic>>[];
      String label(Map<String, dynamic> area) {
        final pin = area['pincode']?.toString() ?? '';
        final locality = area['locality']?.toString().trim() ?? '';
        final district = area['district']?.toString().trim() ?? '';
        final extra = <String>[if (locality.isNotEmpty) locality, if (district.isNotEmpty) district].join(' · ');
        return extra.isEmpty ? pin : pin + ' · ' + extra;
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Align(alignment: Alignment.centerLeft, child: Text('Item availability by PIN code', style: TextStyle(fontWeight: FontWeight.w900))),
        if (widget.allowAllPincodes) ...[
          RadioListTile<String>(
            value: 'all', groupValue: _mode, contentPadding: EdgeInsets.zero,
            title: const Text('Available on all PIN codes'),
            subtitle: const Text('Every active Alteo service area can see this item.'),
            onChanged: (value) {
              if (value == null) return;
              setState(() { _mode = value; _selected.clear(); });
              _emit();
            },
          ),
          RadioListTile<String>(
            value: 'specific', groupValue: _mode, contentPadding: EdgeInsets.zero,
            title: const Text('Available on selected PIN codes'),
            subtitle: const Text('Only selected PIN codes can see this item.'),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _mode = value);
              _emit();
            },
          ),
        ] else
          const Padding(padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Text('Select the PIN codes where customers can order this item.', style: TextStyle(color: Color(0xFF68736D)))),
        if (_mode == 'specific') ...[
          if (areas.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No active PIN codes are configured yet. Admin must add one in Service Areas first.',
                style: TextStyle(color: Color(0xFFB3261E), height: 1.4)))
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDCE6DF)), borderRadius: BorderRadius.circular(12)),
              child: ListView(shrinkWrap: true, children: areas.map((area) {
                final pin = area['pincode']?.toString() ?? '';
                return CheckboxListTile(
                  dense: true, value: _selected.contains(pin), title: Text(label(area)),
                  onChanged: (value) {
                    setState(() { if (value == true) { _selected.add(pin); } else { _selected.remove(pin); } });
                    _emit();
                  },
                );
              }).toList()),
            ),
          const SizedBox(height: 5),
          Text(_selected.isEmpty ? 'Select at least one PIN code to save.' : _selected.length.toString() + ' PIN code(s) selected',
            style: TextStyle(fontSize: 12, color: _selected.isEmpty ? const Color(0xFFB3261E) : _green, fontWeight: FontWeight.w700)),
        ],
      ]);
    },
  );
}

class AlteoOrderItemsSection extends StatefulWidget {
  const AlteoOrderItemsSection({super.key, required this.orderId, this.fallbackDescription});
  final String? orderId;
  final String? fallbackDescription;
  @override
  State<AlteoOrderItemsSection> createState() => _AlteoOrderItemsSectionState();
}

class _AlteoOrderItemsSectionState extends State<AlteoOrderItemsSection> {
  late Future<List<Map<String, dynamic>>> _items = _load();
  Future<List<Map<String, dynamic>>> _load() async {
    final orderId = widget.orderId;
    if (orderId == null || orderId.isEmpty) return <Map<String, dynamic>>[];
    final client = Supabase.instance.client;
    final rows = await client.from('order_items')
      .select('product_id,product_name_snapshot,quantity,unit_price_minor,line_total_minor,status')
      .eq('order_id', orderId).order('created_at');
    final items = List<Map<String, dynamic>>.from(rows as List);
    final productIds = items.map((row) => row['product_id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet().toList();
    if (productIds.isNotEmpty) {
      try {
        final products = await client.from('seller_products').select('id,image_url').inFilter('id', productIds);
        final urls = <String, String>{
          for (final product in (products as List).map((e) => Map<String, dynamic>.from(e as Map)))
            product['id'].toString(): (product['image_url'] ?? '').toString(),
        };
        for (final item in items) { item['image_url'] = urls[item['product_id']?.toString()] ?? ''; }
      } catch (_) {}
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orderId == null || widget.orderId!.isEmpty) {
      final description = widget.fallbackDescription?.trim() ?? '';
      if (description.isEmpty) return const SizedBox.shrink();
      return ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Parcel contents'), subtitle: Text(description));
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _items,
      builder: (context, snapshot) {
        final items = snapshot.data ?? <Map<String, dynamic>>[];
        return ExpansionTile(
          leading: const Icon(Icons.shopping_bag_outlined, color: _green),
          title: const Text('Order items', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: snapshot.hasError ? const Text('Items could not load. Tap to retry.')
            : snapshot.connectionState == ConnectionState.waiting ? const Text('Loading item details…')
            : Text(items.length.toString() + ' item line(s)'),
          onExpansionChanged: (expanded) { if (expanded && snapshot.hasError) setState(() => _items = _load()); },
          children: [
            if (snapshot.hasError)
              Padding(padding: const EdgeInsets.all(12),
                child: TextButton.icon(onPressed: () => setState(() => _items = _load()),
                  icon: const Icon(Icons.refresh_rounded), label: const Text('Retry loading items')))
            else if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
            else if (items.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('No item lines are attached to this order.'))
            else for (final item in items) ...[
              ListTile(
                leading: _thumbnail(item['image_url']?.toString() ?? ''),
                title: Text(
                  item['product_name_snapshot']?.toString() ?? 'Item',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: item['status'] == 'cancelled' ? TextDecoration.lineThrough : null,
                    color: item['status'] == 'cancelled' ? const Color(0xFF858D87) : null,
                  ),
                ),
                subtitle: Text('Qty ' + (item['quantity'] ?? 0).toString() + ' · ₹' +
                  (((item['unit_price_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0) + ' each' +
                  (item['status'] == 'cancelled' ? ' · Cancelled' : '')),
                trailing: Text('₹' + (((item['line_total_minor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(0),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              const Divider(height: 1, indent: 72),
            ],
          ],
        );
      },
    );
  }

  Widget _thumbnail(String url) {
    if (!url.startsWith('https://')) return const CircleAvatar(backgroundColor: _paleGreen, child: Icon(Icons.inventory_2_outlined, color: _green));
    return ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.network(url, width: 48, height: 48, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const CircleAvatar(backgroundColor: _paleGreen, child: Icon(Icons.inventory_2_outlined, color: _green))));
  }
}

class AlteoAppUpdateTile extends StatefulWidget {
  const AlteoAppUpdateTile({super.key, required this.appId});
  final String appId;
  @override
  State<AlteoAppUpdateTile> createState() => _AlteoAppUpdateTileState();
}

class _AlteoAppUpdateTileState extends State<AlteoAppUpdateTile> {
  late Future<Map<String, dynamic>> _data = _load();
  Future<Map<String, dynamic>> _load() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.buildNumber.isEmpty ? info.version : info.version + '+' + info.buildNumber;
    Map<String, dynamic>? release;
    try {
      release = await Supabase.instance.client.from('app_update_manifest')
        .select('latest_version,minimum_supported_version,download_url,release_notes,force_update,published')
        .eq('app_id', widget.appId).eq('published', true).maybeSingle();
    } catch (_) {}
    final latest = release?['latest_version']?.toString() ?? current;
    return {'current': current, 'latest': latest, 'release': release, 'available': release != null && _compareVersion(latest, current) > 0};
  }

  int _compareVersion(String left, String right) {
    List<int> parse(String input) => input.split('+').first.split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9].*$'), '')) ?? 0).toList();
    final a = parse(left), b = parse(right);
    for (var i = 0; i < 3; i++) {
      final av = i < a.length ? a[i] : 0, bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    final buildA = int.tryParse(left.split('+').last) ?? 0;
    final buildB = int.tryParse(right.split('+').last) ?? 0;
    return buildA.compareTo(buildB);
  }

  Future<void> _openRelease(Map<String, dynamic> data) async {
    final release = data['release'] as Map<String, dynamic>?;
    final url = release?['download_url']?.toString() ?? '';
    if (url.isEmpty || !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin has not published a download link for this release yet.')));
      return;
    }
    try {
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the update link.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the update link.')));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _data,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final available = data?['available'] == true;
      final subtitle = snapshot.connectionState == ConnectionState.waiting ? 'Checking the latest published version…'
        : snapshot.hasError ? 'Unable to check for updates. Tap to retry.'
        : available ? 'Version ' + (data?['latest']?.toString() ?? '') + ' is available · Installed ' + (data?['current']?.toString() ?? '')
        : 'Installed version ' + (data?['current']?.toString() ?? 'unknown') + ' · Tap to check again';
      return Card(elevation: 0, child: ListTile(
        leading: CircleAvatar(backgroundColor: available ? const Color(0xFFFFF2D8) : _paleGreen,
          child: Icon(available ? Icons.system_update_alt_rounded : Icons.system_update_rounded,
            color: available ? const Color(0xFF8A5A00) : _green)),
        title: const Text('Check for app updates', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: available
          ? IconButton(tooltip: 'Download update', onPressed: data == null ? null : () => _openRelease(data), icon: const Icon(Icons.download_rounded))
          : IconButton(tooltip: 'Check again', onPressed: () => setState(() => _data = _load()), icon: const Icon(Icons.refresh_rounded)),
        onTap: () { if (available && data != null) { _openRelease(data); } else { setState(() => _data = _load()); } },
      ));
    },
  );
}

class AlteoAppReleaseManager extends StatefulWidget {
  const AlteoAppReleaseManager({super.key});
  @override
  State<AlteoAppReleaseManager> createState() => _AlteoAppReleaseManagerState();
}

class _AlteoAppReleaseManagerState extends State<AlteoAppReleaseManager> {
  static const _apps = <Map<String, String>>[
    {'id':'customer','label':'Customer'}, {'id':'admin','label':'Admin'}, {'id':'seller','label':'Seller'},
    {'id':'driver_partner','label':'Driver Partner'}, {'id':'delivery_partner','label':'Delivery Partner'}, {'id':'dark_store','label':'Dark Store'},
  ];
  late Future<List<Map<String, dynamic>>> _releases = _load();
  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client.from('app_update_manifest').select('*').order('app_id');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final version = TextEditingController(text: row['latest_version']?.toString() ?? '0.1.0+1');
    final minimum = TextEditingController(text: row['minimum_supported_version']?.toString() ?? '');
    final url = TextEditingController(text: row['download_url']?.toString() ?? '');
    final notes = TextEditingController(text: row['release_notes']?.toString() ?? '');
    var published = row['published'] == true;
    var force = row['force_update'] == true;
    try {
      final saved = await showDialog<bool>(context: context, builder: (dc) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text('Release · ' + row['app_id'].toString()),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: version, decoration: const InputDecoration(labelText: 'Latest version *', hintText: '0.2.0+2')),
          const SizedBox(height: 10),
          TextField(controller: minimum, decoration: const InputDecoration(labelText: 'Minimum supported version (optional)')),
          const SizedBox(height: 10),
          TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'HTTPS download / Play Store URL *')),
          const SizedBox(height: 10),
          TextField(controller: notes, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(labelText: 'Release notes')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Published'), subtitle: const Text('Make this update visible in that app profile.'), value: published, onChanged: (v) => setDialogState(() => published = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Critical update'), subtitle: const Text('Label this release as critical. The app still requires user confirmation to install.'), value: force, onChanged: (v) => setDialogState(() => force = v)),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Save release')),
        ],
      )));
      if (saved != true) return;
      if (version.text.trim().isEmpty || !url.text.trim().startsWith('https://')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a version and a valid HTTPS download link.')));
        return;
      }
      await Supabase.instance.client.from('app_update_manifest').upsert({
        'app_id': row['app_id'], 'latest_version': version.text.trim(),
        'minimum_supported_version': minimum.text.trim().isEmpty ? null : minimum.text.trim(),
        'download_url': url.text.trim(), 'release_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'force_update': force, 'published': published,
        'updated_by': Supabase.instance.client.auth.currentUser?.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('App release saved. Profiles will show it without a rebuild.')));
        setState(() => _releases = _load());
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the app release. Check admin permissions and the HTTPS link.')));
    } finally {
      version.dispose(); minimum.dispose(); url.dispose(); notes.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Card(elevation: 0, child: Column(children: [
    const ListTile(leading: Icon(Icons.system_update_alt_rounded, color: _green),
      title: Text('App release management', style: TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text('Publish a version and download link for any Alteo app. Update links appear in that app profile.')),
    FutureBuilder<List<Map<String, dynamic>>>(
      future: _releases,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
        if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(16), child: Text('Release metadata unavailable. Apply the app update migration first.'));
        final rows = snapshot.data ?? <Map<String, dynamic>>[];
        return Column(children: _apps.map((app) {
          Map<String, dynamic>? row;
          for (final candidate in rows) { if (candidate['app_id'] == app['id']) { row = candidate; break; } }
          return ListTile(
            leading: const Icon(Icons.android_rounded),
            title: Text(app['label']!, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(row == null ? 'Not configured' : 'Version ' + row['latest_version'].toString() + ' · ' + (row['published'] == true ? 'Published' : 'Unpublished')),
            trailing: IconButton(tooltip: 'Edit release', icon: const Icon(Icons.edit_outlined), onPressed: row == null ? null : () => _edit(row!)),
          );
        }).toList());
      },
    ),
  ]));
}

class AlteoAppLegalTiles extends StatelessWidget {
  const AlteoAppLegalTiles({super.key, required this.appName});
  final String appName;

  Future<void> _show(BuildContext context, String title, String message) async {
    await showDialog<void>(context: context, builder: (dc) => AlertDialog(
      title: Text(title), content: SingleChildScrollView(child: Text(message, style: const TextStyle(height: 1.5))),
      actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Close'))],
    ));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Card(elevation: 0, child: ListTile(
      leading: const Icon(Icons.privacy_tip_outlined, color: _green), title: const Text('Privacy policy', style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: const Text('Data use, location, notifications and account security'), trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _show(context, 'Alteo privacy policy',
        'Alteo processes the account information needed to provide its services, including profile details, saved addresses, order or ride history, device notification tokens and (when the relevant feature is used) location coordinates. Location is used for serviceability, pickup/drop-off and operational dispatch. Notification permission may be disabled in Android settings.\\n\\nInformation is shared only as needed to fulfil an order or ride, support the account, prevent abuse, and operate the platform. Do not upload sensitive personal information into product descriptions or delivery notes. Keep your Google account secure. You can manage saved addresses and request account deletion in the Customer app settings; partner accounts should contact Alteo Admin for account assistance. Applicable law and retention requirements may require some transaction records to be retained.'),
    )),
    Card(elevation: 0, child: ListTile(
      leading: const Icon(Icons.description_outlined, color: _green), title: const Text('Terms of use', style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: const Text('Responsible use and operational rules'), trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _show(context, 'Alteo terms of use',
        'Use Alteo only with accurate account details and lawful items or services. Customers are responsible for verifying their delivery address and paying eligible cash-on-delivery orders. Sellers must provide accurate product information, prices and availability. Delivery and driver partners must follow assignment, pickup, customer-verification and proof-of-delivery steps; never mark an item delivered before it has been handed over. Admin may pause accounts or listings for safety, compliance or operational reasons. Availability, fares and delivery estimates can depend on service-area configuration. Contact Alteo Admin for unresolved service or account issues.'),
    )),
    Card(elevation: 0, child: ListTile(
      leading: const Icon(Icons.info_outline_rounded, color: _green), title: const Text('About Alteo', style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(appName), trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        final info = await PackageInfo.fromPlatform();
        if (!context.mounted) return;
        await _show(context, 'About ' + appName,
          appName + ' is part of Alteo’s connected marketplace and operations platform. App version: ' + info.version + '+' + info.buildNumber + '. Use this app for the tasks available to your account and role. Keep the app updated for the latest features and security fixes.');
      },
    )),
  ]);
}


/// Displays raster images and SVG catalogue artwork from HTTPS URLs.
/// Flutter's Image.network cannot decode SVG responses; catalogue-item-image
/// is the public Edge Function that returns image/svg+xml.
class AlteoNetworkImage extends StatelessWidget {
  const AlteoNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;

  Widget _fallback(BuildContext context) => fallback ?? Container(
    width: width,
    height: height,
    color: const Color(0xFFEAF2EC),
    alignment: Alignment.center,
    child: const Icon(Icons.image_not_supported_outlined, color: Color(0xFF176B57)),
  );

  @override
  Widget build(BuildContext context) {
    if (!url.startsWith('https://')) return _fallback(context);
    final parsed = Uri.tryParse(url);
    final isSvg = (parsed?.path.toLowerCase().endsWith('.svg') ?? false) ||
        (parsed?.path.contains('/functions/v1/catalogue-item-image') ?? false);
    if (isSvg) {
      return SvgPicture.network(
        url,
        width: width,
        height: height,
        fit: fit,
        placeholderBuilder: (_) => SizedBox(
          width: width,
          height: height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _fallback(context),
    );
  }
}
