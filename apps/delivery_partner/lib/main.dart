import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const appName = 'Alteo Delivery Partner';
const requiredRole = 'delivery_partner';
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://nkerkoptbrcadlpxffkn.supabase.co');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_lM6ttzw8KMPH2BNXgMAJVA_3y1h51YD');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var backendReady = false;
  try {
    if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
      backendReady = true;
    }
  } catch (_) {
    // Public exploration must work even when auth or backend configuration is unavailable.
  }
  runApp(AlteoRoleApp(backendReady: backendReady));
}

class AlteoRoleApp extends StatelessWidget {
  const AlteoRoleApp({super.key, required this.backendReady});
  final bool backendReady;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F6),
      useMaterial3: true,
    ),
    home: RoleExplorePage(backendReady: backendReady),
  );
}

class RoleExplorePage extends StatefulWidget {
  const RoleExplorePage({super.key, required this.backendReady});
  final bool backendReady;
  @override
  State<RoleExplorePage> createState() => _RoleExplorePageState();
}

class _RoleExplorePageState extends State<RoleExplorePage> {
  final phone = TextEditingController();
  final code = TextEditingController();
  bool codeSent = false;
  bool busy = false;
  bool authorized = false;
  String? message;

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> requestCode() async {
    final value = phone.text.trim();
    if (!RegExp(r'^\\+[1-9][0-9]{7,14}$$').hasMatch(value)) {
      setState(() => message = 'Enter your phone number with country code, e.g. +919876543210.');
      return;
    }
    if (!widget.backendReady) {
      setState(() => message = 'Sign-in is temporarily unavailable because the backend is not configured. You can continue exploring this app.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: value);
      if (mounted) setState(() { codeSent = true; message = 'Verification code sent.'; });
    } on AuthException catch (e) {
      if (!mounted) return;
      final lower = e.message.toLowerCase();
      setState(() => message = lower.contains('provider is not enabled') || lower.contains('unsupported provider')
        ? 'Phone sign-in is not enabled in Supabase. Browsing remains available; the owner must enable Phone Auth and configure an SMS provider.'
        : 'Could not send the code: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => message = 'Could not send the code. Check the network and Supabase SMS configuration. You can still explore without signing in.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyCode() async {
    if (!widget.backendReady) return;
    setState(() { busy = true; message = null; });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: phone.text.trim(), token: code.text.trim(), type: OtpType.sms,
      );
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw StateError('Sign-in did not return a user.');
      final row = await Supabase.instance.client.from('user_roles')
        .select('role').eq('user_id', user.id).eq('role', requiredRole).maybeSingle();
      if (row == null) {
        await Supabase.instance.client.auth.signOut();
        if (mounted) setState(() => message = 'This account is not approved for the $requiredRole role. You can still explore public screens.');
      } else if (mounted) {
        setState(() { authorized = true; message = 'Role verified. Protected operations can be connected here.'; });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => message = 'Sign-in failed: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => message = 'Could not verify access: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF176B57), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.explore_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 10),
        const Expanded(child: Text(appName, style: TextStyle(fontWeight: FontWeight.w800))),
      ]),
      actions: [TextButton(onPressed: () => showAuth(context), child: Text(authorized ? 'Access' : 'Sign in'))],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF176B57), Color(0xFF2C8B70)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('EXPLORE ALTEO', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.3, fontSize: 11)),
            const SizedBox(height: 10),
            const Text('Every delivery, clearly tracked', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Explore delivery assignments, pickup, route progress, proof of delivery and earnings.', style: TextStyle(color: Colors.white, height: 1.45)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are already exploring. Sign in is only needed for protected actions.'))),
              icon: const Icon(Icons.explore_outlined), label: const Text('Explore without signing in'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        const Text('Explore features', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('Open any section to learn how it works. Private records and live operations require authorised access.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
        const SizedBox(height: 12),
        for (final feature in _features)
          Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5EAE5))),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
              leading: CircleAvatar(backgroundColor: const Color(0xFFE3F2E9), child: Icon(feature.icon, color: const Color(0xFF176B57))),
              title: Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(feature.subtitle)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showModalBottomSheet<void>(
                context: context, showDragHandle: true, isScrollControlled: true,
                builder: (context) => SafeArea(child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(feature.icon, size: 38, color: const Color(0xFF176B57)),
                    const SizedBox(height: 12),
                    Text(feature.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(feature.detail, style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 14),
                    const Text('Exploration is public. Changes to real orders, money, inventory or partner assignments are restricted to authorised accounts.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Continue exploring'))),
                  ]),
                )),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EAE5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(widget.backendReady ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: const Color(0xFF176B57)),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.backendReady
              ? 'Public exploration is available. Live data and protected actions depend on backend permissions and service configuration.'
              : 'Public exploration is available. Sign-in and live data are temporarily unavailable until backend configuration is restored.',
              style: const TextStyle(height: 1.45))),
          ]),
        ),
      ],
    ),
  );

  Future<void> showAuth(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(22, 8, 22, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sign in to Alteo', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Browsing is open to everyone. Sign in only to access protected operations.', style: TextStyle(height: 1.4)),
          const SizedBox(height: 16),
          TextField(controller: phone, enabled: !codeSent, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone with country code', hintText: '+919876543210', border: OutlineInputBorder())),
          if (codeSent) ...[
            const SizedBox(height: 12),
            TextField(controller: code, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SMS verification code', border: OutlineInputBorder())),
          ],
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(message!, style: TextStyle(color: message!.contains('sent') || message!.contains('verified') ? Colors.green : Colors.red, height: 1.4)),
          ],
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: busy ? null : () async {
              setSheetState(() {});
              if (codeSent) { await verifyCode(); } else { await requestCode(); }
              setSheetState(() {});
            },
            child: Text(busy ? 'Please wait…' : codeSent ? 'Verify and continue' : 'Send verification code'),
          )),
          TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Continue exploring')),
        ])),
      )),
    );
    if (mounted) setState(() {});
  }
}

class _Feature {
  const _Feature(this.title, this.subtitle, this.detail, this.icon);
  final String title, subtitle, detail;
  final IconData icon;
}

const _features = <_Feature>[
  _Feature('Delivery assignments', 'Orders routed to eligible partners', 'Assignments are created by admin or dispatch rules and delivered through shared backend updates.', Icons.assignment_rounded),
  _Feature('Pickup and drop', 'Update delivery milestones', 'Authorised partners can confirm pickup, en route and delivery status with server-side validation.', Icons.local_shipping_rounded),
  _Feature('Navigation', 'Reach the right location', 'Delivery destinations and customer contact details are restricted to the assigned task.', Icons.map_rounded),
  _Feature('Earnings', 'Delivery totals and payouts', 'View personal earnings only after a verified account is connected.', Icons.account_balance_wallet_rounded),
  _Feature('Help and safety', 'Support for active deliveries', 'Access guidance for delays, failed delivery and safe handling of parcels.', Icons.support_agent_rounded),
];
).hasMatch(value)) {
      setState(() => message = 'Enter your phone number with country code, e.g. +919876543210.');
      return;
    }
    if (!widget.backendReady) {
      setState(() => message = 'Sign-in is temporarily unavailable because the backend is not configured. You can continue exploring this app.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: value);
      if (mounted) setState(() { codeSent = true; message = 'Verification code sent.'; });
    } on AuthException catch (e) {
      if (!mounted) return;
      final lower = e.message.toLowerCase();
      setState(() => message = lower.contains('provider is not enabled') || lower.contains('unsupported provider')
        ? 'Phone sign-in is not enabled in Supabase. Browsing remains available; the owner must enable Phone Auth and configure an SMS provider.'
        : 'Could not send the code: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => message = 'Could not send the code. Check the network and Supabase SMS configuration. You can still explore without signing in.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyCode() async {
    if (!widget.backendReady) return;
    setState(() { busy = true; message = null; });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: phone.text.trim(), token: code.text.trim(), type: OtpType.sms,
      );
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw StateError('Sign-in did not return a user.');
      final row = await Supabase.instance.client.from('user_roles')
        .select('role').eq('user_id', user.id).eq('role', requiredRole).maybeSingle();
      if (row == null) {
        await Supabase.instance.client.auth.signOut();
        if (mounted) setState(() => message = 'This account is not approved for the $requiredRole role. You can still explore public screens.');
      } else if (mounted) {
        setState(() { authorized = true; message = 'Role verified. Protected operations can be connected here.'; });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => message = 'Sign-in failed: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => message = 'Could not verify access: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF176B57), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.explore_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 10),
        const Expanded(child: Text(appName, style: TextStyle(fontWeight: FontWeight.w800))),
      ]),
      actions: [TextButton(onPressed: () => showAuth(context), child: Text(authorized ? 'Access' : 'Sign in'))],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF176B57), Color(0xFF2C8B70)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('EXPLORE ALTEO', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.3, fontSize: 11)),
            const SizedBox(height: 10),
            const Text('Every delivery, clearly tracked', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Explore delivery assignments, pickup, route progress, proof of delivery and earnings.', style: TextStyle(color: Colors.white, height: 1.45)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are already exploring. Sign in is only needed for protected actions.'))),
              icon: const Icon(Icons.explore_outlined), label: const Text('Explore without signing in'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        const Text('Explore features', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('Open any section to learn how it works. Private records and live operations require authorised access.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
        const SizedBox(height: 12),
        for (final feature in _features)
          Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5EAE5))),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
              leading: CircleAvatar(backgroundColor: const Color(0xFFE3F2E9), child: Icon(feature.icon, color: const Color(0xFF176B57))),
              title: Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(feature.subtitle)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showModalBottomSheet<void>(
                context: context, showDragHandle: true, isScrollControlled: true,
                builder: (context) => SafeArea(child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(feature.icon, size: 38, color: const Color(0xFF176B57)),
                    const SizedBox(height: 12),
                    Text(feature.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(feature.detail, style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 14),
                    const Text('Exploration is public. Changes to real orders, money, inventory or partner assignments are restricted to authorised accounts.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Continue exploring'))),
                  ]),
                )),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EAE5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(widget.backendReady ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: const Color(0xFF176B57)),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.backendReady
              ? 'Public exploration is available. Live data and protected actions depend on backend permissions and service configuration.'
              : 'Public exploration is available. Sign-in and live data are temporarily unavailable until backend configuration is restored.',
              style: const TextStyle(height: 1.45))),
          ]),
        ),
      ],
    ),
  );

  Future<void> showAuth(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(22, 8, 22, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sign in to Alteo', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Browsing is open to everyone. Sign in only to access protected operations.', style: TextStyle(height: 1.4)),
          const SizedBox(height: 16),
          TextField(controller: phone, enabled: !codeSent, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone with country code', hintText: '+919876543210', border: OutlineInputBorder())),
          if (codeSent) ...[
            const SizedBox(height: 12),
            TextField(controller: code, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SMS verification code', border: OutlineInputBorder())),
          ],
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(message!, style: TextStyle(color: message!.contains('sent') || message!.contains('verified') ? Colors.green : Colors.red, height: 1.4)),
          ],
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: busy ? null : () async {
              setSheetState(() {});
              if (codeSent) { await verifyCode(); } else { await requestCode(); }
              setSheetState(() {});
            },
            child: Text(busy ? 'Please wait…' : codeSent ? 'Verify and continue' : 'Send verification code'),
          )),
          TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Continue exploring')),
        ])),
      )),
    );
    if (mounted) setState(() {});
  }
}

class _Feature {
  const _Feature(this.title, this.subtitle, this.detail, this.icon);
  final String title, subtitle, detail;
  final IconData icon;
}

const _features = <_Feature>[
  _Feature('Delivery assignments', 'Orders routed to eligible partners', 'Assignments are created by admin or dispatch rules and delivered through shared backend updates.', Icons.assignment_rounded),
  _Feature('Pickup and drop', 'Update delivery milestones', 'Authorised partners can confirm pickup, en route and delivery status with server-side validation.', Icons.local_shipping_rounded),
  _Feature('Navigation', 'Reach the right location', 'Delivery destinations and customer contact details are restricted to the assigned task.', Icons.map_rounded),
  _Feature('Earnings', 'Delivery totals and payouts', 'View personal earnings only after a verified account is connected.', Icons.account_balance_wallet_rounded),
  _Feature('Help and safety', 'Support for active deliveries', 'Access guidance for delays, failed delivery and safe handling of parcels.', Icons.support_agent_rounded),
];
