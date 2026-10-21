import 'package:alteo_role_app/alteo_role_app.dart';

Future<void> main() => launchAlteoWorkspace(
  definition: const WorkspaceDefinition(appName: 'Alteo Seller', roleLabel: 'Seller workspace', requiredRole: 'seller', sections: [
    WorkspaceSection(label: 'Products', table: 'seller_products', columns: 'id,name,kind,price_minor,currency,status,created_at', titleColumn: 'name', subtitleColumns: ['kind', 'price_minor', 'currency', 'status'],),
    WorkspaceSection(label: 'Orders', table: 'orders', columns: 'id,status,total_minor,currency,created_at', titleColumn: 'status', subtitleColumns: ['total_minor', 'currency', 'created_at']),
    WorkspaceSection(label: 'Inventory', table: 'seller_inventory', columns: 'id,product_id,stock_on_hand,reserved_quantity,updated_at', titleColumn: 'product_id', subtitleColumns: ['stock_on_hand', 'reserved_quantity', 'updated_at']),
  ]),
  supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
  supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
