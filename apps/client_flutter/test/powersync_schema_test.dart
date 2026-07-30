import 'package:client_flutter/data/powersync/powersync_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Lifly PowerSync schema relies on the automatic id column', () {
    expect(() => liflyPowerSyncSchema.validate(), returnsNormally);
    expect(liflyPowerSyncSchema.tables, isNotEmpty);

    for (final table in liflyPowerSyncSchema.tables) {
      expect(
        table.columns.where((column) => column.name == 'id'),
        isEmpty,
        reason:
            '${table.name} must not declare the PowerSync-managed id column',
      );
    }
  });
}
