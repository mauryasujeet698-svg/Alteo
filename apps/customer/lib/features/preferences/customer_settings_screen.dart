import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/core/widgets/catalogue_preview_notice.dart';
import 'package:customer/features/preferences/app_preferences_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomerSettingsScreen extends ConsumerWidget {
  const CustomerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesStoreProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Preferences', style: Theme.of(context).textTheme.headlineMedium)),
      body: ListenableBuilder(
        listenable: preferences,
        builder: (context, child) => ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const CataloguePreviewNotice(),
            const SizedBox(height: 20),
            Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.settings_suggest_outlined)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {preferences.themeMode},
              onSelectionChanged: (values) => preferences.setThemeMode(values.first),
            ),
            const SizedBox(height: 24),
            Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow notifications'),
              subtitle: const Text('Local preference only; push registration and server preferences are not connected yet.'),
              value: preferences.notificationsEnabled,
              onChanged: preferences.setNotificationsEnabled,
            ),
            const SizedBox(height: 24),
            Text('Language', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.language_outlined),
              title: Text('English'),
              subtitle: Text('Additional languages can be added when localisation resources are implemented.'),
              trailing: Icon(Icons.check_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Help & support', style: Theme.of(context).textTheme.headlineMedium)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AlteoColors.mint, borderRadius: BorderRadius.circular(20)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.support_agent_rounded, color: AlteoColors.forest, size: 30),
              SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('How can we help?', style: TextStyle(color: AlteoColors.forestDeep, fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('Help content below is a starting point. Ticket creation and contact channels need the support backend.', style: TextStyle(color: AlteoColors.forestDeep, fontSize: 13, height: 1.4)),
              ])),
            ]),
          ),
          const SizedBox(height: 20),
          Text('Frequently asked questions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const ExpansionTile(
            title: Text('Can I browse without signing in?'),
            children: [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Yes. Public service discovery and preview catalogues are available without an account. Account-dependent actions will ask you to sign in.'))],
          ),
          const ExpansionTile(
            title: Text('Why can’t I place an order yet?'),
            children: [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('This build uses preview catalogue content. Live inventory, server-side price quotes, payment verification and order fulfilment must be connected before real orders can be accepted.'))],
          ),
          const ExpansionTile(
            title: Text('Are the displayed prices live?'),
            children: [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('No. Sample prices are included only to develop and test the interface. Always verify prices from Alteo’s live backend before enabling checkout.'))],
          ),
          const ExpansionTile(
            title: Text('How is my location used?'),
            children: [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('The preferred location currently stores a label on this device. GPS, routing and serviceability checks are not connected yet.'))],
          ),
        ],
      ),
    );
  }
}

class PrivacyAccountScreen extends StatelessWidget {
  const PrivacyAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Privacy & security', style: Theme.of(context).textTheme.headlineMedium)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const CataloguePreviewNotice(),
          const SizedBox(height: 18),
          Text('Your account and data', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Alteo is being built with guest browsing and Google sign-in. Account data access, downloadable personal data, consent records and remote account deletion must be implemented with the backend before this app is released.'),
          const SizedBox(height: 18),
          Card(child: ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Delete account'),
            subtitle: const Text('Not available until the secure account-deletion service is implemented.'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Account deletion is not connected'),
                content: const Text('No account or data has been deleted. The secure deletion request and confirmation workflow must be connected before this action can be enabled.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
              ),
            ),
          )),
          const SizedBox(height: 8),
          Text('Security information', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Never send passwords, payment card details or authentication secrets to support. This preview does not collect payment details. Production data handling must be described accurately in the published privacy policy.'),
        ],
      ),
    );
  }
}
