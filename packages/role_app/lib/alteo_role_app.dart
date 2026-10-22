import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkspaceSection {
  const WorkspaceSection({required this.label, required this.table, required this.columns, required this.titleColumn, this.subtitleColumns = const [], this.ownerColumn, this.filters = const {}});
  final String label, table, columns, titleColumn;
  final List<String> subtitleColumns;
  final String? ownerColumn;
  final Map<String, Object> filters;
}
class WorkspaceDefinition {
  const WorkspaceDefinition({required this.appName, required this.roleLabel, required this.sections, this.requiredRole});
  final String appName, roleLabel;
  final String? requiredRole;
  final List<WorkspaceSection> sections;
}

/// Starts a live Supabase-backed app. No mock authentication or demo records.
Future<void> launchAlteoWorkspace({required WorkspaceDefinition definition, required String supabaseUrl, required String supabaseAnonKey}) async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseClient? client;
  String? error;
  if (supabaseUrl.trim().isEmpty || supabaseAnonKey.trim().isEmpty) {
    error = 'Set SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define.';
  } else {
    try {
      await Supabase.initialize(url: supabaseUrl.trim(), anonKey: supabaseAnonKey.trim());
      client = Supabase.instance.client;
    } catch (_) {
      error = 'Supabase could not be initialized. Check app configuration.';
    }
  }
  runApp(_Root(definition: definition, client: client, error: error));
}
class _Root extends StatelessWidget {
  const _Root({required this.definition, required this.client, required this.error});
  final WorkspaceDefinition definition;
  final SupabaseClient? client;
  final String? error;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: definition.appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)), useMaterial3: true),
    home: client == null ? _ConfigPage(appName: definition.appName, message: error!) : _AuthGate(definition: definition, client: client!),
  );
}
class _ConfigPage extends StatelessWidget {
  const _ConfigPage({required this.appName, required this.message});
  final String appName, message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(appName)),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.settings_outlined, size: 56), const SizedBox(height: 16),
      Text(message, textAlign: TextAlign.center), const SizedBox(height: 8),
      const Text('No demo account or fake data is enabled. Configure Supabase before signing in.', textAlign: TextAlign.center),
    ]))),
  );
}
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.definition, required this.client});
  final WorkspaceDefinition definition;
  final SupabaseClient client;
  @override
  State<_AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<_AuthGate> {
  User? user;
  bool checkingRole = false, busy = false, otpSent = false, usePhone = false;
  String? authError, roleError;
  late final TextEditingController phone, otp;
  late final StreamSubscription<AuthState> authSubscription;
  @override
  void initState() {
    super.initState();
    phone = TextEditingController();
    otp = TextEditingController();
    user = widget.client.auth.currentUser;
    authSubscription = widget.client.auth.onAuthStateChange.listen((event) {
      final signedInUser = event.session?.user;
      if (signedInUser != null) {
        enforceRole(signedInUser);
      } else if (mounted) {
        setState(() { user = null; checkingRole = false; });
      }
    });
    if (user != null) enforceRole(user!);
  }
  @override
  void dispose() { authSubscription.cancel(); phone.dispose(); otp.dispose(); super.dispose(); }

  Future<void> googleSignIn() async {
    setState(() { busy = true; authError = null; roleError = null; });
    try {
      await widget.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'alteo://login-callback',
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => authError = e.message);
    } catch (_) {
      if (mounted) setState(() => authError = 'Google sign-in could not start. Check Supabase Google provider and redirect settings.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> sendOtp() async {
    final value = phone.text.trim();
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value)) {
      setState(() => authError = 'Enter a phone number with country code, for example +919876543210.');
      return;
    }
    setState(() { busy = true; authError = null; });
    try {
      await widget.client.auth.signInWithOtp(phone: value);
      if (mounted) setState(() => otpSent = true);
    } catch (_) {
      if (mounted) setState(() => authError = 'OTP could not be sent. Check SMS provider setup and retry.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> verifyOtp() async {
    final value = otp.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      setState(() => authError = 'Enter the six-digit code sent to your phone.');
      return;
    }
    setState(() { busy = true; authError = null; });
    try {
      final result = await widget.client.auth.verifyOTP(phone: phone.text.trim(), token: value, type: OtpType.sms);
      if (result.user == null) throw const AuthException('No user in verification response.');
      await enforceRole(result.user!);
    } on AuthException catch (e) {
      if (mounted) setState(() => authError = e.message);
    } catch (_) {
      if (mounted) setState(() => authError = 'Verification failed. Check the code and try again.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> enforceRole(User value) async {
    final role = widget.definition.requiredRole;
    if (role == null) { if (mounted) setState(() { user = value; roleError = null; }); return; }
    if (mounted) setState(() => checkingRole = true);
    try {
      final rows = await widget.client.from('user_roles').select('role').eq('user_id', value.id).eq('role', role).limit(1);
      if (rows.isEmpty) {
        await widget.client.auth.signOut();
        if (mounted) setState(() { user = null; roleError = 'This account is not approved for the ' + widget.definition.roleLabel + ' workspace. Contact Alteo support.'; });
      } else if (mounted) { setState(() { user = value; roleError = null; }); }
    } catch (_) {
      await widget.client.auth.signOut();
      if (mounted) setState(() { user = null; roleError = 'Could not verify workspace permissions. Retry when online.'; });
    } finally { if (mounted) setState(() => checkingRole = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (checkingRole) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (user != null) return _Home(definition: widget.definition, client: widget.client, user: user!, onSignOut: () async {
      await widget.client.auth.signOut();
      if (mounted) setState(() { user = null; otpSent = false; usePhone = false; otp.clear(); roleError = null; });
    });
    return Scaffold(
      appBar: AppBar(title: Text(widget.definition.appName)),
      body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.lock_outline, size: 54), const SizedBox(height: 12),
          Text(widget.definition.roleLabel, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Continue with Google. Partner access is verified against server-managed Supabase roles.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          if (!usePhone) ...[
            FilledButton.icon(
              onPressed: busy ? null : googleSignIn,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
            ),
            TextButton(
              onPressed: busy ? null : () => setState(() { usePhone = true; authError = null; }),
              child: const Text('Use phone number instead'),
            ),
          ] else ...[
            TextField(controller: phone, keyboardType: TextInputType.phone, autocorrect: false,
              decoration: const InputDecoration(labelText: 'Phone number (optional)', hintText: '+919876543210', border: OutlineInputBorder())),
            if (otpSent) ...[
              const SizedBox(height: 12),
              TextField(controller: otp, keyboardType: TextInputType.number, maxLength: 6,
                decoration: const InputDecoration(labelText: 'SMS verification code', border: OutlineInputBorder())),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: busy ? null : (otpSent ? verifyOtp : sendOtp), child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(otpSent ? 'Verify and sign in' : 'Send OTP')),
            TextButton(onPressed: busy ? null : () => setState(() { usePhone = false; otpSent = false; otp.clear(); authError = null; }),
              child: const Text('Back to Google sign-in')),
          ],
          if (authError != null || roleError != null) ...[
            const SizedBox(height: 8), Text(authError ?? roleError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (busy) const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: CircularProgressIndicator())),
        ]),
      )))),
    );
  }
}
class _Home extends StatefulWidget {
  const _Home({required this.definition, required this.client, required this.user, required this.onSignOut});
  final WorkspaceDefinition definition;
  final SupabaseClient client;
  final User user;
  final Future<void> Function() onSignOut;
  @override
  State<_Home> createState() => _HomeState();
}
class _HomeState extends State<_Home> {
  int selected = 0;
  late Future<List<Map<String, dynamic>>> rows;
  WorkspaceSection get section => widget.definition.sections[selected];
  @override
  void initState() { super.initState(); rows = loadRows(); }
  Future<List<Map<String, dynamic>>> loadRows() async {
    final s = section;
    dynamic query = widget.client.from(s.table).select(s.columns).limit(20);
    if (s.ownerColumn != null) query = query.eq(s.ownerColumn!, widget.user.id);
    for (final filter in s.filters.entries) { query = query.eq(filter.key, filter.value); }
    final result = await query;
    return (result as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }
  void choose(int index) => setState(() { selected = index; rows = loadRows(); });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.definition.appName), actions: [
      IconButton(tooltip: 'Refresh', onPressed: () => setState(() => rows = loadRows()), icon: const Icon(Icons.refresh)),
      IconButton(tooltip: 'Sign out', onPressed: widget.onSignOut, icon: const Icon(Icons.logout)),
    ]),
    body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(section.label, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Signed in • ' + (widget.user.phone ?? widget.user.email ?? widget.user.id)),
        const SizedBox(height: 4),
        const Text('Records come from Supabase and remain subject to backend row policies.'),
      ])),
      Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(future: rows, builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _StateMessage(icon: Icons.cloud_off_outlined,
          message: 'Could not load ' + section.label.toLowerCase() + '. Check connection and backend policies.',
          detail: 'Fake records are not substituted.', action: () => setState(() => rows = loadRows()));
        final values = snapshot.data ?? const [];
        if (values.isEmpty) return _StateMessage(icon: Icons.inbox_outlined, message: 'Nothing here yet',
          detail: 'Records appear when the service is configured and real data exists.',
          action: () => setState(() => rows = loadRows()));
        return RefreshIndicator(onRefresh: () async { setState(() => rows = loadRows()); }, child: ListView.separated(
          padding: const EdgeInsets.all(16), itemCount: values.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = values[index];
            final title = row[section.titleColumn]?.toString() ?? 'Record';
            final detail = section.subtitleColumns.where((key) => row[key] != null && row[key].toString().isNotEmpty)
              .map((key) => _label(key) + ': ' + row[key].toString()).join(' • ');
            return Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: detail.isEmpty ? null : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis)));
          },
        ));
      })),
    ])),
    bottomNavigationBar: NavigationBar(selectedIndex: selected, onDestinationSelected: choose, destinations: widget.definition.sections.map((s) => NavigationDestination(
      icon: const Icon(Icons.circle_outlined), selectedIcon: const Icon(Icons.circle), label: s.label)).toList()),
  );
}
class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.message, required this.detail, required this.action});
  final IconData icon;
  final String message, detail;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 48), const SizedBox(height: 12),
    Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 6), Text(detail, textAlign: TextAlign.center), const SizedBox(height: 12),
    OutlinedButton.icon(onPressed: action, icon: const Icon(Icons.refresh), label: const Text('Try again')),
  ])));
}
String _label(String key) => key.replaceAll('_minor', '').replaceAll('_', ' ');
