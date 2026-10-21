import 'package:alteo_role_app/alteo_role_app.dart';

Future<void> main() => launchAlteoWorkspace(
  definition: const WorkspaceDefinition(appName: 'Alteo Delivery Partner', roleLabel: 'Delivery partner', requiredRole: 'delivery_partner', sections: [
    WorkspaceSection(label: 'Assignments', table: 'delivery_jobs', columns: 'id,status,customer_id,created_at', titleColumn: 'status', subtitleColumns: ['created_at'], ownerColumn: 'delivery_partner_id'),
    WorkspaceSection(label: 'Earnings', table: 'delivery_earnings', columns: 'id,amount_minor,currency,created_at', titleColumn: 'amount_minor', subtitleColumns: ['currency', 'created_at'], ownerColumn: 'delivery_partner_id'),
    WorkspaceSection(label: 'Profile', table: 'profiles', columns: 'id,display_name,created_at', titleColumn: 'display_name', subtitleColumns: ['created_at'], ownerColumn: 'id'),
  ]),
  supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
  supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
