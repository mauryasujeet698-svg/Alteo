import 'package:alteo_role_app/alteo_role_app.dart';
import 'package:alteo_customer/src/config/app_config.dart';
import 'package:alteo_customer/src/services/mapbox_service.dart';

Future<void> main() async {
  const definition = WorkspaceDefinition(
    appName: 'Alteo Customer',
    roleLabel: 'Customer account',
    sections: [
      WorkspaceSection(label: 'Explore', table: 'seller_products', columns: 'id,name,kind,price_minor,currency,status', titleColumn: 'name', subtitleColumns: ['kind', 'price_minor', 'currency'], filters: {'status': 'active'}),
      WorkspaceSection(label: 'Orders', table: 'orders', columns: 'id,status,total_minor,currency,created_at', titleColumn: 'status', subtitleColumns: ['total_minor', 'currency', 'created_at'], ownerColumn: 'customer_id'),
      WorkspaceSection(label: 'Rides', table: 'rides', columns: 'id,status,pickup_label,destination_label,fare_minor,created_at', titleColumn: 'status', subtitleColumns: ['pickup_label', 'destination_label', 'fare_minor', 'created_at'], ownerColumn: 'customer_id'),
      WorkspaceSection(label: 'Parcels', table: 'delivery_jobs', columns: 'id,status,created_at', titleColumn: 'status', subtitleColumns: ['created_at'], ownerColumn: 'customer_id'),
      WorkspaceSection(label: 'Account', table: 'profiles', columns: 'id,display_name,avatar_url,created_at', titleColumn: 'display_name', subtitleColumns: ['created_at'], ownerColumn: 'id'),
    ],
  );
  final config = AppConfig.fromEnvironment();
  MapboxService.configure(config.mapboxPublicToken);
  await launchAlteoWorkspace(definition: definition, supabaseUrl: config.supabaseUrl, supabaseAnonKey: config.supabaseAnonKey);
}
