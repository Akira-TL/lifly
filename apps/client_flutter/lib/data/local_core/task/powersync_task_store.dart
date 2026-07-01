import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/task/local_task_mapper.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

class PowerSyncTaskStore {
  final SyncService syncService;
  final LocalCoreWritePolicy policy;
  final LocalCoreAuditLogWriter auditLogWriter;

  factory PowerSyncTaskStore({
    required SyncService syncService,
    LocalCoreWritePolicy? policy,
    LocalCoreAuditLogWriter? auditLogWriter,
  }) {
    final resolvedPolicy = policy ?? LocalCoreWritePolicy();
    return PowerSyncTaskStore._(
      syncService: syncService,
      policy: resolvedPolicy,
      auditLogWriter:
          auditLogWriter ?? LocalCoreAuditLogWriter(policy: resolvedPolicy),
    );
  }

  const PowerSyncTaskStore._({
    required this.syncService,
    required this.policy,
    required this.auditLogWriter,
  });

  Future<LocalTaskRecord> createTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final createInput = LocalTaskCreateInput.fromMap(input);
    final metadata = policy.metadataForCreate(context);
    final task = LocalTaskRecord(
      id: policy.nextEntityId('task'),
      title: createInput.title,
      description: createInput.description,
      dueAt: createInput.dueAt,
      remindAt: createInput.remindAt,
      priority: createInput.priority,
      taskStatus: 'todo',
      completedAt: null,
      status: 'active',
      revision: metadata.revision,
      createdAt: metadata.timestamps.createdAt,
      updatedAt: metadata.timestamps.updatedAt,
    );

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      await _insertTask(handle, task, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'task.create',
          entityType: 'task',
          entityId: task.id,
          afterSnapshot: LocalTaskMapper.snapshot(task),
        ),
      );
    });

    return task;
  }

  Future<List<LocalTaskRecord>> listTasks(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final listInput = LocalTaskListInput.fromMap(input);
    final rows = await _listRows(
      taskStatus: listInput.taskStatus,
      limit: listInput.limit,
    );
    return rows.map(LocalTaskMapper.fromRow).toList(growable: false);
  }

  Future<LocalTaskRecord> updateTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final updateInput = LocalTaskUpdateInput.fromMap(input);
    late final LocalTaskRecord updatedTask;

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final oldTask = await _findActiveTask(handle, updateInput.taskId);
      if (oldTask == null) {
        throw StateError('Task not found: ${updateInput.taskId}');
      }

      final metadata = policy.metadataForUpdate(
        context,
        currentRevision: oldTask.revision,
        createdAt: oldTask.createdAt,
      );
      updatedTask = LocalTaskRecord(
        id: oldTask.id,
        title: updateInput.title ?? oldTask.title,
        description: updateInput.hasDescription
            ? updateInput.description
            : oldTask.description,
        dueAt: updateInput.hasDueAt ? updateInput.dueAt : oldTask.dueAt,
        remindAt: updateInput.hasRemindAt
            ? updateInput.remindAt
            : oldTask.remindAt,
        priority: updateInput.priority ?? oldTask.priority,
        taskStatus: updateInput.taskStatus ?? oldTask.taskStatus,
        completedAt: oldTask.completedAt,
        status: oldTask.status,
        revision: metadata.revision,
        createdAt: oldTask.createdAt,
        updatedAt: metadata.timestamps.updatedAt,
      );

      await _updateTask(handle, updatedTask, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'task.update',
          entityType: 'task',
          entityId: updatedTask.id,
          beforeSnapshot: LocalTaskMapper.snapshot(oldTask),
          afterSnapshot: LocalTaskMapper.snapshot(updatedTask),
        ),
      );
    });

    return updatedTask;
  }

  Future<List<Map<String, Object?>>> _listRows({
    required String? taskStatus,
    required int limit,
  }) async {
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT id, title, description, due_at, remind_at, priority, task_status, '
      'completed_at, status, revision, created_at, updated_at '
      'FROM tasks '
      'WHERE status = ? AND (? IS NULL OR task_status = ?) '
      'ORDER BY updated_at DESC '
      'LIMIT ?',
      ['active', taskStatus, taskStatus, limit],
    );
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<LocalTaskRecord?> _findActiveTask(
    LocalCoreWriteHandle handle,
    String taskId,
  ) async {
    final row = await handle.getOptional(
      'SELECT id, title, description, due_at, remind_at, priority, task_status, '
      'completed_at, status, revision, created_at, updated_at '
      'FROM tasks WHERE id = ? AND status = ?',
      [taskId, 'active'],
    );
    return row == null ? null : LocalTaskMapper.fromRow(row);
  }

  Future<void> _insertTask(
    LocalCoreWriteHandle handle,
    LocalTaskRecord task,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'INSERT INTO tasks('
      'id, user_id, title, description, due_at, remind_at, priority, task_status, '
      'source, status, created_at, updated_at, revision'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        task.id,
        metadata.userId,
        task.title,
        task.description,
        task.dueAt?.toIso8601String(),
        task.remindAt?.toIso8601String(),
        task.priority,
        task.taskStatus,
        metadata.source,
        task.status,
        metadata.timestamps.createdAtIso,
        metadata.timestamps.updatedAtIso,
        metadata.revision,
      ],
    );
  }

  Future<void> _updateTask(
    LocalCoreWriteHandle handle,
    LocalTaskRecord task,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'UPDATE tasks SET title = ?, description = ?, due_at = ?, remind_at = ?, '
      'priority = ?, task_status = ?, updated_at = ?, revision = ? '
      'WHERE id = ? AND status = ?',
      [
        task.title,
        task.description,
        task.dueAt?.toIso8601String(),
        task.remindAt?.toIso8601String(),
        task.priority,
        task.taskStatus,
        metadata.timestamps.updatedAtIso,
        metadata.revision,
        task.id,
        'active',
      ],
    );
  }
}
