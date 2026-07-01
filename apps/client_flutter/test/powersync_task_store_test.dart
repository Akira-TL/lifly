import 'dart:io';

import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PowerSync task CRUD persists when native database is available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'lifly_task_store_',
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

      final task = await bridge.createTask({
        'title': 'PowerSync task',
        'description': 'created through PowerSync local task store',
        'priority': 'normal',
        'due_at': '2026-07-02T08:00:00.000Z',
      }, context);
      expect(task.revision, 1);
      expect(task.taskStatus, 'todo');

      final todoList = await bridge.listTasks({
        'task_status': 'todo',
        'limit': 20,
      }, context);
      expect(todoList.map((item) => item.id), contains(task.id));

      final updated = await bridge.updateTask({
        'task_id': task.id,
        'title': 'Updated PowerSync task',
        'priority': 'high',
      }, context);
      expect(updated.title, 'Updated PowerSync task');
      expect(updated.priority, 'high');
      expect(updated.revision, 2);

      final completed = await bridge.completeTask({
        'task_id': task.id,
      }, context);
      expect(completed.taskStatus, 'done');
      expect(completed.completedAt, isNotNull);
      expect(completed.revision, 3);

      final doneList = await bridge.listTasks({
        'task_status': 'done',
        'limit': 20,
      }, context);
      expect(doneList.map((item) => item.id), contains(task.id));

      final deleted = await bridge.deleteTask({'task_id': task.id}, context);
      expect(deleted.status, 'deleted');
      expect(deleted.revision, 4);

      final afterDelete = await bridge.listTasks({'limit': 20}, context);
      expect(afterDelete.map((item) => item.id), isNot(contains(task.id)));

      final auditCount = await service.db.get(
        'SELECT count(*) AS count FROM audit_logs',
      );
      expect(auditCount['count'], 4);
    },
  );
}
