import 'package:alteo_role_app/alteo_role_app.dart';

Future<void> main() => launchAlteoWorkspace(
  definition: const WorkspaceDefinition(appName: 'Alteo Admin', roleLabel: 'Administrator', requiredRole: 'admin', sections: [
    WorkspaceSection(label: 'Orders', table: 'orders', columns: 'id,status,total_minor,currency,created_at', titleColumn: 'status', subtitleColumns: ['total_minor', 'currency', 'created_at']),
    WorkspaceSection(label: 'Sellers', table: 'sellers', columns: 'id,display_name,status,created_at', titleColumn: 'display_name', subtitleColumns: ['status', 'created_at']),
    WorkspaceSection(label: 'Support', table: 'support_tickets', columns: 'id,subject,status,created_at', titleColumn: 'subject', subtitleColumns: ['status', 'created_at']),
    WorkspaceSection(label: 'Users', table: 'profiles', columns: 'id,display_name,created_at', titleColumn: 'display_name', subtitleColumns: ['created_at']),
    WorkspaceSection(label: 'Audit', table: 'audit_events', columns: 'id,action,created_at', titleColumn: 'action', subtitleColumns: ['created_at']),
  ]),
  supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
  supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
