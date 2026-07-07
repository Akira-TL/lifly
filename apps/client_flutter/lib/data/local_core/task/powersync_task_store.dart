import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/task/local_task_mapper.dart';
import 'package:client_flutter/data/local_core/task/local_task_reminder_strategy_engine.dart';
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
      await _insertTask(
        handle,
        task,
        metadata,
        sourceCaptureId: createInput.sourceCaptureId,
      );
      await _replaceSuggestedStrategy(handle, task, context);
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
    final rows = await _listRows(taskStatus: listInput.taskStatus, limit: 100);
    final strategies = await _strategyMap();
    final tasks = rows
        .map(LocalTaskMapper.fromRow)
        .where((task) {
          return _matchesTaskGroup(
            task,
            listInput.group,
            context.effectiveNow,
            strategies[task.id],
          );
        })
        .take(listInput.limit);
    return tasks.toList(growable: false);
  }

  Future<LocalTaskRecord> deleteTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final deleteInput = LocalTaskDeleteInput.fromMap(input);
    late final LocalTaskRecord deletedTask;

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final oldTask = await _findActiveTask(handle, deleteInput.taskId);
      if (oldTask == null) {
        throw StateError('Task not found: ${deleteInput.taskId}');
      }

      final metadata = policy.metadataForUpdate(
        context,
        currentRevision: oldTask.revision,
        createdAt: oldTask.createdAt,
      );
      deletedTask = LocalTaskRecord(
        id: oldTask.id,
        title: oldTask.title,
        description: oldTask.description,
        dueAt: oldTask.dueAt,
        remindAt: oldTask.remindAt,
        priority: oldTask.priority,
        taskStatus: oldTask.taskStatus,
        completedAt: oldTask.completedAt,
        status: deleteInput.status,
        revision: metadata.revision,
        createdAt: oldTask.createdAt,
        updatedAt: metadata.timestamps.updatedAt,
      );

      await _softDeleteTask(handle, deletedTask, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'task.delete',
          entityType: 'task',
          entityId: deletedTask.id,
          beforeSnapshot: LocalTaskMapper.snapshot(oldTask),
          afterSnapshot: LocalTaskMapper.snapshot(deletedTask),
        ),
      );
    });

    return deletedTask;
  }

  Future<LocalTaskRecord> completeTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final completeInput = LocalTaskCompleteInput.fromMap(input);
    late final LocalTaskRecord completedTask;

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final oldTask = await _findActiveTask(handle, completeInput.taskId);
      if (oldTask == null) {
        throw StateError('Task not found: ${completeInput.taskId}');
      }

      final metadata = policy.metadataForUpdate(
        context,
        currentRevision: oldTask.revision,
        createdAt: oldTask.createdAt,
      );
      completedTask = LocalTaskRecord(
        id: oldTask.id,
        title: oldTask.title,
        description: oldTask.description,
        dueAt: oldTask.dueAt,
        remindAt: oldTask.remindAt,
        priority: oldTask.priority,
        taskStatus: 'done',
        completedAt: metadata.timestamps.updatedAt,
        status: oldTask.status,
        revision: metadata.revision,
        createdAt: oldTask.createdAt,
        updatedAt: metadata.timestamps.updatedAt,
      );

      await _completeTask(handle, completedTask, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'task.complete',
          entityType: 'task',
          entityId: completedTask.id,
          beforeSnapshot: LocalTaskMapper.snapshot(oldTask),
          afterSnapshot: LocalTaskMapper.snapshot(completedTask),
        ),
      );
    });

    return completedTask;
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
      await _replaceSuggestedStrategy(handle, updatedTask, context);
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

  Future<Map<String, LocalTaskReminderStrategy>> listTaskReminderStrategies() {
    return _strategyMap();
  }

  Future<LocalTaskReminderStrategy?> getTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    if (taskId == null || taskId.trim().isEmpty) {
      throw ArgumentError('task_id is required');
    }
    await syncService.ensureInitialized();
    final row = await syncService.db.getOptional(
      'SELECT id, task_id, warning_level, warning_reason, preparation_window_days, '
      'ai_suggested_remind_at, strategy_status, source, confirmed_at, dismissed_at, created_at, updated_at '
      'FROM task_reminder_strategies '
      'WHERE task_id = ? AND strategy_status != ? '
      'ORDER BY updated_at DESC LIMIT 1',
      [taskId, 'dismissed'],
    );
    return row == null ? null : _strategyFromRow(row);
  }

  Future<LocalTaskReminderStrategy?> generateTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    if (taskId == null || taskId.trim().isEmpty) {
      throw ArgumentError('task_id is required');
    }
    await syncService.ensureInitialized();
    final task = await _findTaskById(taskId);
    if (task == null) throw StateError('Task not found: $taskId');
    final strategy = await LocalCoreWriteExecutor(syncService: syncService)
        .run<LocalTaskReminderStrategy?>((handle) async {
      return _replaceSuggestedStrategy(handle, task, context);
    });
    return strategy;
  }

  Future<LocalTaskReminderStrategy> confirmTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final strategy = await _upsertStrategy(input, context, 'confirmed');
    final remindAt = strategy.aiSuggestedRemindAt;
    if (remindAt != null) {
      await updateTask({
        'task_id': strategy.taskId,
        'remind_at': remindAt.toIso8601String(),
      }, context);
      await _upsertTaskReminderRecord(strategy, context);
    }
    return strategy;
  }

  Future<LocalTaskReminderStrategy> dismissTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    return _upsertStrategy(input, context, 'dismissed');
  }

  Future<LocalTaskReminderStrategy> _upsertStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
    String status,
  ) async {
    final strategyId =
        input['strategy_id'] as String? ?? input['id'] as String?;
    final taskId = input['task_id'] as String?;
    if (strategyId == null && (taskId == null || taskId.trim().isEmpty)) {
      throw ArgumentError(
        'task_id is required when strategy_id is not provided',
      );
    }
    await syncService.ensureInitialized();
    final existing = strategyId == null
        ? await syncService.db.getOptional(
            'SELECT id FROM task_reminder_strategies WHERE task_id = ? AND strategy_status != ? ORDER BY updated_at DESC LIMIT 1',
            [taskId, 'dismissed'],
          )
        : null;
    final now = context.effectiveNow.toUtc().toIso8601String();
    final id = strategyId ?? existing?['id'] as String? ?? policy.nextEntityId('task_strategy');
    await syncService.db.execute(
      'INSERT OR REPLACE INTO task_reminder_strategies('
      'id, user_id, task_id, warning_level, warning_reason, preparation_window_days, '
      'ai_suggested_remind_at, strategy_status, source, confirmed_at, dismissed_at, created_at, updated_at'
      ') VALUES (?, ?, coalesce((SELECT task_id FROM task_reminder_strategies WHERE id = ?), ?), '
      'coalesce(?, (SELECT warning_level FROM task_reminder_strategies WHERE id = ?), ?), '
      'coalesce(?, (SELECT warning_reason FROM task_reminder_strategies WHERE id = ?)), '
      'coalesce(?, (SELECT preparation_window_days FROM task_reminder_strategies WHERE id = ?)), '
      'coalesce(?, (SELECT ai_suggested_remind_at FROM task_reminder_strategies WHERE id = ?)), ?, '
      'coalesce(?, (SELECT source FROM task_reminder_strategies WHERE id = ?), ?), ?, ?, '
      'coalesce((SELECT created_at FROM task_reminder_strategies WHERE id = ?), ?), ?)',
      [
        id,
        context.userId,
        id,
        taskId,
        input['warning_level'] as String?,
        id,
        'normal',
        input['warning_reason'] as String?,
        id,
        input['preparation_window_days'] as int?,
        id,
        input['ai_suggested_remind_at'] as String?,
        id,
        status,
        input['source'] as String?,
        id,
        'user',
        status == 'confirmed' ? now : null,
        status == 'dismissed' ? now : null,
        id,
        now,
        now,
      ],
    );
    final row = await syncService.db.get(
      'SELECT id, task_id, warning_level, warning_reason, preparation_window_days, '
      'ai_suggested_remind_at, strategy_status, source, confirmed_at, dismissed_at, created_at, updated_at '
      'FROM task_reminder_strategies WHERE id = ?',
      [id],
    );
    return _strategyFromRow(row);
  }

  Future<List<LocalReminderRecord>> listTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final status = input['status'] as String? ?? input['reminder_status'] as String? ?? 'pending';
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT id, target_type, target_id, remind_at, channel, reminder_status, created_at '
      'FROM reminders WHERE target_type = ? AND reminder_status = ? ORDER BY remind_at ASC',
      ['task', status],
    );
    return rows.map(_reminderFromRow).toList(growable: false);
  }

  Future<LocalTaskReminderStrategy?> _replaceSuggestedStrategy(
    LocalCoreWriteHandle handle,
    LocalTaskRecord task,
    LocalCoreContext context,
  ) async {
    final existing = await handle.getOptional(
      'SELECT id, strategy_status FROM task_reminder_strategies '
      'WHERE task_id = ? AND strategy_status != ? ORDER BY updated_at DESC LIMIT 1',
      [task.id, 'dismissed'],
    );
    if (existing?['strategy_status'] == 'confirmed') {
      return null;
    }
    final suggestion = const LocalTaskReminderStrategyEngine().suggest(
      task,
      now: context.effectiveNow,
    );
    if (suggestion == null) return null;
    if (existing != null) {
      await handle.execute(
        'DELETE FROM task_reminder_strategies WHERE id = ? AND source = ? AND strategy_status = ?',
        [existing['id'], 'ai', 'suggested'],
      );
    }
    final now = context.effectiveNow.toUtc().toIso8601String();
    final id = policy.nextEntityId('task_strategy');
    await handle.execute(
      'INSERT INTO task_reminder_strategies('
      'id, user_id, task_id, warning_level, warning_reason, preparation_window_days, '
      'ai_suggested_remind_at, strategy_status, source, created_at, updated_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        context.userId,
        task.id,
        suggestion.warningLevel,
        suggestion.warningReason,
        suggestion.preparationWindowDays,
        suggestion.aiSuggestedRemindAt?.toIso8601String(),
        'suggested',
        'ai',
        now,
        now,
      ],
    );
    final row = await handle.getOptional(
      'SELECT id, task_id, warning_level, warning_reason, preparation_window_days, '
      'ai_suggested_remind_at, strategy_status, source, confirmed_at, dismissed_at, created_at, updated_at '
      'FROM task_reminder_strategies WHERE id = ?',
      [id],
    );
    return row == null ? null : _strategyFromRow(row);
  }

  Future<void> _upsertTaskReminderRecord(
    LocalTaskReminderStrategy strategy,
    LocalCoreContext context,
  ) async {
    final remindAt = strategy.aiSuggestedRemindAt;
    if (remindAt == null) return;
    await syncService.ensureInitialized();
    final now = context.effectiveNow.toUtc().toIso8601String();
    final existing = await syncService.db.getOptional(
      'SELECT id FROM reminders WHERE target_type = ? AND target_id = ? AND channel = ? AND reminder_status = ? '
      'ORDER BY created_at DESC LIMIT 1',
      ['task', strategy.taskId, 'app', 'pending'],
    );
    if (existing == null) {
      await syncService.db.execute(
        'INSERT INTO reminders(id, user_id, target_type, target_id, remind_at, channel, reminder_status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          policy.nextEntityId('reminder'),
          context.userId,
          'task',
          strategy.taskId,
          remindAt.toIso8601String(),
          'app',
          'pending',
          now,
        ],
      );
    } else {
      await syncService.db.execute(
        'UPDATE reminders SET remind_at = ?, reminder_status = ? WHERE id = ?',
        [remindAt.toIso8601String(), 'pending', existing['id']],
      );
    }
  }

  LocalReminderRecord _reminderFromRow(Map<String, Object?> row) {
    return LocalReminderRecord(
      id: row['id'] as String,
      targetType: row['target_type'] as String? ?? 'task',
      targetId: row['target_id'] as String,
      remindAt: _readDateTime(row['remind_at']),
      channel: row['channel'] as String? ?? 'app',
      status: row['reminder_status'] as String? ?? 'pending',
      createdAt: _readDateTime(row['created_at']),
    );
  }

  Future<LocalTaskRecord?> _findTaskById(String taskId) async {
    final row = await syncService.db.getOptional(
      'SELECT id, title, description, due_at, remind_at, priority, task_status, completed_at, status, revision, created_at, updated_at '
      'FROM tasks WHERE id = ? AND status = ?',
      [taskId, 'active'],
    );
    return row == null ? null : LocalTaskMapper.fromRow(row);
  }

  Future<Map<String, LocalTaskReminderStrategy>> _strategyMap() async {
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT id, task_id, warning_level, warning_reason, preparation_window_days, '
      'ai_suggested_remind_at, strategy_status, source, confirmed_at, dismissed_at, created_at, updated_at '
      'FROM task_reminder_strategies WHERE strategy_status != ? ORDER BY updated_at DESC',
      ['dismissed'],
    );
    final result = <String, LocalTaskReminderStrategy>{};
    for (final row in rows) {
      final strategy = _strategyFromRow(row);
      result.putIfAbsent(strategy.taskId, () => strategy);
    }
    return result;
  }

  bool _matchesTaskGroup(
    LocalTaskRecord task,
    String group,
    DateTime now,
    LocalTaskReminderStrategy? strategy,
  ) {
    if (group == 'all') return true;
    if (task.taskStatus != 'todo' && task.taskStatus != 'doing') return false;
    final dueAt = task.dueAt;
    if (group == 'urgent') {
      return strategy?.warningLevel == 'critical' ||
          task.priority == 'urgent' ||
          (dueAt != null && dueAt.isBefore(now));
    }
    if (group == 'warning') {
      return strategy?.warningLevel == 'warning' ||
          task.priority == 'high' ||
          (dueAt != null &&
              dueAt.isAfter(now) &&
              dueAt.difference(now).inDays <= 3);
    }
    if (group == 'today') {
      if (dueAt == null) return false;
      final left = dueAt.toUtc();
      final right = now.toUtc();
      return left.year == right.year &&
          left.month == right.month &&
          left.day == right.day;
    }
    return true;
  }

  LocalTaskReminderStrategy _strategyFromRow(Map<String, Object?> row) {
    return LocalTaskReminderStrategy(
      id: row['id'] as String,
      taskId: row['task_id'] as String,
      warningLevel: row['warning_level'] as String? ?? 'normal',
      warningReason: row['warning_reason'] as String?,
      preparationWindowDays: row['preparation_window_days'] as int?,
      aiSuggestedRemindAt: _readDateTimeOrNull(row['ai_suggested_remind_at']),
      strategyStatus: row['strategy_status'] as String? ?? 'suggested',
      source: row['source'] as String? ?? 'ai',
      confirmedAt: _readDateTimeOrNull(row['confirmed_at']),
      dismissedAt: _readDateTimeOrNull(row['dismissed_at']),
      createdAt: _readDateTime(row['created_at']),
      updatedAt: _readDateTime(row['updated_at']),
    );
  }

  DateTime _readDateTime(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw ArgumentError('Expected ISO datetime string, got $value');
  }

  DateTime? _readDateTimeOrNull(Object? value) {
    if (value == null) return null;
    return _readDateTime(value);
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
    LocalCoreWriteMetadata metadata, {
    String? sourceCaptureId,
  }) async {
    await handle.execute(
      'INSERT INTO tasks('
      'id, user_id, title, description, due_at, remind_at, priority, task_status, '
      'source_capture_id, source, status, created_at, updated_at, revision'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        task.id,
        metadata.userId,
        task.title,
        task.description,
        task.dueAt?.toIso8601String(),
        task.remindAt?.toIso8601String(),
        task.priority,
        task.taskStatus,
        sourceCaptureId,
        metadata.source,
        task.status,
        metadata.timestamps.createdAtIso,
        metadata.timestamps.updatedAtIso,
        metadata.revision,
      ],
    );
  }

  Future<void> _softDeleteTask(
    LocalCoreWriteHandle handle,
    LocalTaskRecord task,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'UPDATE tasks SET status = ?, deleted_at = ?, updated_at = ?, revision = ? '
      'WHERE id = ? AND status = ?',
      [
        task.status,
        metadata.timestamps.updatedAtIso,
        metadata.timestamps.updatedAtIso,
        metadata.revision,
        task.id,
        'active',
      ],
    );
  }

  Future<void> _completeTask(
    LocalCoreWriteHandle handle,
    LocalTaskRecord task,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'UPDATE tasks SET task_status = ?, completed_at = ?, updated_at = ?, revision = ? '
      'WHERE id = ? AND status = ?',
      [
        task.taskStatus,
        task.completedAt?.toIso8601String(),
        metadata.timestamps.updatedAtIso,
        metadata.revision,
        task.id,
        'active',
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
