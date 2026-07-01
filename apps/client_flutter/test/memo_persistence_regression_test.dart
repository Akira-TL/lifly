import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/powersync_persistence_harness.dart';

void main() {
  test(
    'memo survives database restart with revision, soft delete, and audit logs',
    () async {
      final harness = await PowerSyncPersistenceHarness.create(
        'lifly_memo_persistence_',
      );
      addTearDown(harness.dispose);

      final firstService = await harness.openService();
      if (firstService == null) return;

      final firstBridge = PowerSyncLocalCoreBridge(syncService: firstService);
      final context = LocalCoreContext.flutterUser(
        now: DateTime.utc(2026, 7, 2, 10),
      );

      final memo = await firstBridge.createMemo({
        'type': 'memo',
        'title': 'Persistent memo',
        'content_markdown': 'memo body before restart',
        'tags': ['persistence'],
      }, context);
      final updated = await firstBridge.updateMemo({
        'memo_id': memo.id,
        'title': 'Updated persistent memo',
        'content_markdown': 'memo body after update',
        'tags': ['persistence', 'updated'],
      }, context);

      expect(updated.revision, 2);
      firstService.dispose();

      final secondService = await harness.openService();
      expect(secondService, isNotNull);
      final secondBridge = PowerSyncLocalCoreBridge(
        syncService: secondService!,
      );

      final afterRestart = await secondBridge.searchMemos({
        'q': 'after update',
        'limit': 20,
      }, context);
      expect(afterRestart.map((item) => item.id), contains(memo.id));
      final persisted = afterRestart.singleWhere((item) => item.id == memo.id);
      expect(persisted.revision, 2);
      expect(persisted.title, 'Updated persistent memo');
      expect(persisted.tags, ['persistence', 'updated']);

      final deleted = await secondBridge.deleteMemo({
        'memo_id': memo.id,
      }, context);
      expect(deleted.revision, 3);
      secondService.dispose();

      final thirdService = await harness.openService();
      expect(thirdService, isNotNull);
      final thirdBridge = PowerSyncLocalCoreBridge(syncService: thirdService!);

      final visibleAfterDelete = await thirdBridge.searchMemos({
        'q': 'persistent',
        'limit': 20,
      }, context);
      expect(
        visibleAfterDelete.map((item) => item.id),
        isNot(contains(memo.id)),
      );

      final deletedRow = await thirdService.db.get(
        'SELECT status, revision FROM memos WHERE id = ?',
        [memo.id],
      );
      expect(deletedRow['status'], 'deleted');
      expect(deletedRow['revision'], 3);

      final auditCount = await thirdService.db.get(
        'SELECT count(*) AS count FROM audit_logs WHERE entity_type = ? AND entity_id = ?',
        ['memo', memo.id],
      );
      expect(auditCount['count'], 3);
      thirdService.dispose();
    },
  );
}
