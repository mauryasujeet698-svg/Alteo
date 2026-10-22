import 'package:flutter_test/flutter_test.dart';
import 'package:alteo_role_app/alteo_role_app.dart';

void main() {
  test('workspace sections declare their backend contract', () {
    const section = WorkspaceSection(
      label: 'My records',
      table: 'orders',
      columns: 'id,status',
      titleColumn: 'status',
      ownerColumn: 'customer_id',
    );
    expect(section.table, 'orders');
    expect(section.columns, 'id,status');
    expect(section.ownerColumn, 'customer_id');
  });
}
