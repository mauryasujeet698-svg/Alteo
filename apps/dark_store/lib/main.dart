import 'package:alteo_role_app/alteo_role_app.dart';

Future<void> main() => launchAlteoWorkspace(
  definition: const WorkspaceDefinition(appName: 'Alteo Dark Store', roleLabel: 'Dark store operator', requiredRole: 'dark_store', sections: [
    WorkspaceSection(label: 'Stock', table: 'dark_store_inventory', columns: 'id,product_id,stock_on_hand,reserved_quantity,updated_at', titleColumn: 'product_id', subtitleColumns: ['stock_on_hand', 'reserved_quantity', 'updated_at']),
    WorkspaceSection(label: 'Orders', table: 'orders', columns: 'id,status,total_minor,currency,created_at', titleColumn: 'status', subtitleColumns: ['total_minor', 'currency', 'created_at']),
    WorkspaceSection(label: 'Fulfilment', table: 'delivery_jobs', columns: 'id,status,created_at', titleColumn: 'status', subtitleColumns: ['created_at']),
  ]),
  supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
  supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
