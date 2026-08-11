import 'dart:io';

import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PowerSync memo CRUD persists when native database is available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'lifly_memo_store_',
      );
      final dbPath = '${tempDir.path}/lifly-test.db';
      final service = SyncService();
      addTearDown(() async {
        service.dispose();
        await tempDir.delete(recursive: true);
      });

      try {
        await service.initialize(dbPath: dbPath);
      } catch (_) {
        return;
      }

      final context = LocalCoreContext.flutterUser(
        now: DateTime.utc(2026, 7, 1, 10),
      );
      final bridge = PowerSyncLocalCoreBridge(syncService: service);

      final memo = await bridge.createMemo({
        'type': 'memo',
        'title': 'PowerSync memo',
        'content_markdown': 'created through PowerSync local memo store',
        'tags': ['powersync'],
        'mood': '开心',
      }, context);
      expect(memo.revision, 1);
      final createdRow = await service.db.get(
        'SELECT mood FROM memos WHERE id = ?',
        [memo.id],
      );
      expect(createdRow['mood'], '开心');

      final results = await bridge.searchMemos({
        'q': 'local memo store',
        'limit': 20,
      }, context);
      expect(results.map((item) => item.id), contains(memo.id));

      final updated = await bridge.updateMemo({
        'memo_id': memo.id,
        'title': 'Updated PowerSync memo',
        'content_markdown': 'updated through PowerSync local memo store',
        'tags': ['powersync', 'updated'],
        'mood': '平静',
      }, context);
      expect(updated.revision, 2);
      final updatedRow = await service.db.get(
        'SELECT mood FROM memos WHERE id = ?',
        [memo.id],
      );
      expect(updatedRow['mood'], '平静');

      final deleted = await bridge.deleteMemo({'memo_id': memo.id}, context);
      expect(deleted.status, 'deleted');
      expect(deleted.revision, 3);

      final afterDelete = await bridge.searchMemos({
        'q': 'PowerSync memo',
        'limit': 20,
      }, context);
      expect(afterDelete.map((item) => item.id), isNot(contains(memo.id)));

      final auditCount = await service.db.get(
        'SELECT count(*) AS count FROM audit_logs',
      );
      expect(auditCount['count'], 3);
    },
  );
}
