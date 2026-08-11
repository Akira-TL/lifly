import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/powersync_persistence_harness.dart';

void main() {
  test(
    'task survives database restart with status, soft delete, and audit logs',
    () async {
      final harness = await PowerSyncPersistenceHarness.create(
        'lifly_task_persistence_',
      );
      addTearDown(harness.dispose);

      final firstService = await harness.openService();
      if (firstService == null) return;

      final firstBridge = PowerSyncLocalCoreBridge(syncService: firstService);
      final context = LocalCoreContext.flutterUser(
        now: DateTime.utc(2026, 7, 2, 11),
      );

      final task = await firstBridge.createTask({
        'title': 'Persistent task',
        'description': 'task before restart',
        'priority': 'normal',
      }, context);
      final updated = await firstBridge.updateTask({
        'task_id': task.id,
        'title': 'Updated persistent task',
        'priority': 'high',
      }, context);

      expect(updated.revision, 2);
      firstService.dispose();

      final secondService = await harness.openService();
      expect(secondService, isNotNull);
      final secondBridge = PowerSyncLocalCoreBridge(
        syncService: secondService!,
      );

      final todoAfterRestart = await secondBridge.listTasks({
        'task_status': 'todo',
        'limit': 20,
      }, context);
      expect(todoAfterRestart.map((item) => item.id), contains(task.id));
      final persisted = todoAfterRestart.singleWhere(
        (item) => item.id == task.id,
      );
      expect(persisted.revision, 2);
      expect(persisted.priority, 'high');

      final completed = await secondBridge.completeTask({
        'task_id': task.id,
      }, context);
      expect(completed.taskStatus, 'done');
      expect(completed.revision, 3);
      secondService.dispose();

      final thirdService = await harness.openService();
      expect(thirdService, isNotNull);
      final thirdBridge = PowerSyncLocalCoreBridge(syncService: thirdService!);

      final doneAfterRestart = await thirdBridge.listTasks({
        'task_status': 'done',
        'limit': 20,
      }, context);
      expect(doneAfterRestart.map((item) => item.id), contains(task.id));
      final doneTask = doneAfterRestart.singleWhere(
        (item) => item.id == task.id,
      );
      expect(doneTask.completedAt, isNotNull);
      expect(doneTask.revision, 3);

      final deleted = await thirdBridge.deleteTask({
        'task_id': task.id,
      }, context);
      expect(deleted.status, 'user_trashed');
      expect(deleted.revision, 4);
      thirdService.dispose();

      final fourthService = await harness.openService();
      expect(fourthService, isNotNull);
      final fourthBridge = PowerSyncLocalCoreBridge(
        syncService: fourthService!,
      );

      final visibleAfterDelete = await fourthBridge.listTasks({
        'limit': 20,
      }, context);
      expect(
        visibleAfterDelete.map((item) => item.id),
        isNot(contains(task.id)),
      );

      final deletedRow = await fourthService.db.get(
        'SELECT status, revision, task_status, completed_at FROM tasks WHERE id = ?',
        [task.id],
      );
      expect(deletedRow['status'], 'user_trashed');
      expect(deletedRow['revision'], 4);
      expect(deletedRow['task_status'], 'done');
      expect(deletedRow['completed_at'], isNotNull);

      final restored = await fourthBridge.restoreTask({
        'task_id': task.id,
      }, context);
      expect(restored.status, 'active');
      expect(restored.revision, 5);

      final visibleAfterRestore = await fourthBridge.listTasks({
        'task_status': 'done',
        'limit': 20,
      }, context);
      expect(visibleAfterRestore.map((item) => item.id), contains(task.id));

      final restoredRow = await fourthService.db.get(
        'SELECT status, revision, deleted_at FROM tasks WHERE id = ?',
        [task.id],
      );
      expect(restoredRow['status'], 'active');
      expect(restoredRow['revision'], 5);
      expect(restoredRow['deleted_at'], isNull);

      final auditRows = await fourthService.db.getAll(
        'SELECT action FROM audit_logs WHERE entity_type = ? AND entity_id = ? ORDER BY created_at',
        ['task', task.id],
      );
      expect(auditRows, hasLength(5));
      expect(auditRows.last['action'], 'task.restore');
      fourthService.dispose();

      final fifthService = await harness.openService();
      expect(fifthService, isNotNull);
      final fifthBridge = PowerSyncLocalCoreBridge(syncService: fifthService!);
      final visibleAfterRestoreRestart = await fifthBridge.listTasks({
        'task_status': 'done',
        'limit': 20,
      }, context);
      expect(
        visibleAfterRestoreRestart.map((item) => item.id),
        contains(task.id),
      );
      fifthService.dispose();
    },
  );

  test('task status edits persist completedAt transitions', () async {
    final harness = await PowerSyncPersistenceHarness.create(
      'lifly_task_completed_at_',
    );
    addTearDown(harness.dispose);

    final service = await harness.openService();
    if (service == null) return;
    final bridge = PowerSyncLocalCoreBridge(syncService: service);
    final context = LocalCoreContext.flutterUser(
      now: DateTime.utc(2026, 8, 11, 8),
    );
    final task = await bridge.createTask({'title': 'Status edit task'}, context);

    final done = await bridge.updateTask({
      'task_id': task.id,
      'task_status': 'done',
    }, context);
    expect(done.completedAt, DateTime.utc(2026, 8, 11, 8));
    final doneRow = await service.db.get(
      'SELECT task_status, completed_at FROM tasks WHERE id = ?',
      [task.id],
    );
    expect(doneRow['task_status'], 'done');
    expect(doneRow['completed_at'], isNotNull);

    final reopened = await bridge.updateTask({
      'task_id': task.id,
      'task_status': 'doing',
    }, context);
    expect(reopened.completedAt, isNull);
    final reopenedRow = await service.db.get(
      'SELECT task_status, completed_at FROM tasks WHERE id = ?',
      [task.id],
    );
    expect(reopenedRow['task_status'], 'doing');
    expect(reopenedRow['completed_at'], isNull);
    service.dispose();
  });
}
