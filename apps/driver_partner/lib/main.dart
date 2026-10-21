import 'package:alteo_role_app/alteo_role_app.dart';

Future<void> main() => launchAlteoWorkspace(
  definition: const WorkspaceDefinition(appName: 'Alteo Driver Partner', roleLabel: 'Driver partner', requiredRole: 'driver_partner', sections: [
    WorkspaceSection(label: 'Trips', table: 'rides', columns: 'id,status,pickup_label,destination_label,fare_minor,created_at', titleColumn: 'status', subtitleColumns: ['pickup_label', 'destination_label', 'fare_minor', 'created_at'], ownerColumn: 'driver_id'),
    WorkspaceSection(label: 'Requests', table: 'rides', columns: 'id,status,pickup_label,destination_label,created_at', titleColumn: 'status', subtitleColumns: ['pickup_label', 'destination_label', 'created_at'], filters: {'status': 'requested'}),
    WorkspaceSection(label: 'Earnings', table: 'driver_earnings', columns: 'id,amount_minor,currency,created_at', titleColumn: 'amount_minor', subtitleColumns: ['currency', 'created_at'], ownerColumn: 'driver_id'),
  ]),
  supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
  supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
