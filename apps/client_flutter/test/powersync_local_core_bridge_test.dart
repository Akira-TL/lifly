import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PowerSyncLocalCoreBridge reports health or diagnostic error', () async {
    final service = SyncService();
    addTearDown(service.dispose);

    final health = await PowerSyncLocalCoreBridge(syncService: service).health();

    expect(health.mode, 'powersync');
    expect(health.version, '0.2.1');
    expect(health.checkedAt, isNotNull);
    expect(health.status, anyOf('ok', 'error'));

    if (health.status == 'error') {
      expect(health.detail, isNot(isEmpty));
    } else {
      expect(health.detail, contains('database initialized'));
    }
  });
}
