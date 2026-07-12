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

  test(
    'PowerSync reminder dispatch lifecycle persists retries and delivery',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'lifly_reminder_store_',
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

      final now = DateTime.utc(2026, 7, 11, 10);
      final context = LocalCoreContext.flutterUser(now: now);
      final bridge = PowerSyncLocalCoreBridge(syncService: service);
      final task = await bridge.createTask({
        'title': '提醒派发测试',
        'description': '验证失败、重试和送达状态',
        'due_at': now.add(const Duration(hours: 2)).toIso8601String(),
      }, context);
      await bridge.confirmTaskReminderStrategy({
        'task_id': task.id,
        'ai_suggested_remind_at': now.toIso8601String(),
        'warning_level': 'warning',
      }, context);

      final claimed = await bridge.claimDueTaskReminders({
        'now': now.toIso8601String(),
        'limit': 10,
      }, context);
      expect(claimed, hasLength(1));
      expect(claimed.single.status, 'pending');
      expect(claimed.single.attemptCount, 1);
      expect(claimed.single.dispatchToken, isNotNull);
      expect(claimed.single.title, '提醒派发测试');

      final failed = await bridge.markTaskReminderFailed({
        'reminder_id': claimed.single.id,
        'dispatch_token': claimed.single.dispatchToken,
        'error': 'notification permission denied',
        'retry_after_seconds': 0,
      }, context);
      expect(failed.status, 'failed');
      expect(failed.lastError, 'notification permission denied');
      expect(failed.nextAttemptAt, now);

      final retried = await bridge.retryTaskReminder({
        'reminder_id': failed.id,
        'reset_attempts': true,
      }, context);
      expect(retried.status, 'pending');
      expect(retried.attemptCount, 0);

      final claimedAgain = await bridge.claimDueTaskReminders({
        'now': now.toIso8601String(),
        'limit': 10,
      }, context);
      final delivered = await bridge.markTaskReminderDelivered({
        'reminder_id': claimedAgain.single.id,
        'dispatch_token': claimedAgain.single.dispatchToken,
        'external_id': 'desktop-notification-1',
      }, context);
      expect(delivered.status, 'delivered');
      expect(delivered.externalId, 'desktop-notification-1');
      expect(delivered.deliveredAt, now);

      final rows = await bridge.listTaskReminders({
        'status': 'delivered',
      }, context);
      expect(rows.single.id, delivered.id);
      expect(rows.single.revision, greaterThanOrEqualTo(6));

      final reminderAuditCount = await service.db.get(
        "SELECT count(*) AS count FROM audit_logs WHERE entity_type = 'reminder'",
      );
      expect(reminderAuditCount['count'], greaterThanOrEqualTo(4));
    },
  );
}
