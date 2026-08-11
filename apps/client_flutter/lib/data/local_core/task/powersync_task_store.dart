import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/task/local_task_mapper.dart';
import 'package:client_flutter/data/local_core/task/local_task_reminder_strategy_engine.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

part 'powersync_task_helpers.dart';

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
    final rows = await _listRows(
      syncService,
      taskStatus: listInput.taskStatus,
      limit: 100,
    );
    final strategies = await _strategyMap(syncService);
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
      await _cancelActiveTaskReminders(
        auditLogWriter,
        handle,
        deletedTask.id,
        context,
      );
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

  Future<LocalTaskRecord> restoreTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    if (taskId == null || taskId.trim().isEmpty) {
      throw ArgumentError('task_id is required');
    }
    late final LocalTaskRecord restoredTask;

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final oldTask = await _findTrashedTask(handle, taskId);
      if (oldTask == null) {
        throw StateError('Task not found in trash: $taskId');
      }
      final metadata = policy.metadataForUpdate(
        context,
        currentRevision: oldTask.revision,
        createdAt: oldTask.createdAt,
      );
      restoredTask = LocalTaskRecord(
        id: oldTask.id,
        title: oldTask.title,
        description: oldTask.description,
        dueAt: oldTask.dueAt,
        remindAt: oldTask.remindAt,
        priority: oldTask.priority,
        taskStatus: oldTask.taskStatus,
        completedAt: oldTask.completedAt,
        status: 'active',
        revision: metadata.revision,
        createdAt: oldTask.createdAt,
        updatedAt: metadata.timestamps.updatedAt,
      );
      await _restoreTask(handle, restoredTask, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'task.restore',
          entityType: 'task',
          entityId: restoredTask.id,
          beforeSnapshot: LocalTaskMapper.snapshot(oldTask),
          afterSnapshot: LocalTaskMapper.snapshot(restoredTask),
        ),
      );
    });

    return restoredTask;
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
      await _cancelActiveTaskReminders(
        auditLogWriter,
        handle,
        completedTask.id,
        context,
      );
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
      if (updatedTask.taskStatus == 'done' ||
          updatedTask.taskStatus == 'cancelled') {
        await _cancelActiveTaskReminders(
          auditLogWriter,
          handle,
          updatedTask.id,
          context,
        );
      } else {
        await _replaceSuggestedStrategy(handle, updatedTask, context);
      }
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
    return _strategyMap(syncService);
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
    final task = await _findTaskById(syncService, taskId);
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
      await _upsertTaskReminderRecord(
        syncService,
        policy,
        strategy,
        context,
      );
    }
    return strategy;
  }

  Future<LocalTaskReminderStrategy> dismissTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final strategy = await _upsertStrategy(input, context, 'dismissed');
    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      await _cancelActiveTaskReminders(
        auditLogWriter,
        handle,
        strategy.taskId,
        context,
      );
    });
    return strategy;
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
    final status = input.containsKey('status')
        ? input['status'] as String?
        : input['reminder_status'] as String? ?? 'pending';
    final limit = (input['limit'] as int?) ?? 100;
    final dueBefore = _readDateTimeOrNull(input['due_before']);
    await syncService.ensureInitialized();
    final conditions = <String>[
      'r.user_id = ?',
      'r.target_type = ?',
    ];
    final parameters = <Object?>[context.userId, 'task'];
    if (status != null && status.isNotEmpty) {
      _validateReminderStatus(status);
      conditions.add('r.reminder_status = ?');
      parameters.add(status);
    }
    if (dueBefore != null) {
      conditions.add('r.remind_at <= ?');
      parameters.add(dueBefore.toIso8601String());
    }
    parameters.add(limit);
    final rows = await syncService.db.getAll(
      '${_reminderSelectSql()} WHERE ${conditions.join(' AND ')} '
      'ORDER BY r.remind_at ASC, r.created_at ASC LIMIT ?',
      parameters,
    );
    return rows.map(_reminderFromRow).toList(growable: false);
  }

  Future<List<LocalReminderRecord>> claimDueTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final limit = (input['limit'] as int?) ?? 20;
    if (limit < 1 || limit > 50) {
      throw ArgumentError('limit must be between 1 and 50');
    }
    final leaseSeconds = (input['lease_seconds'] as int?) ?? 120;
    if (leaseSeconds < 15 || leaseSeconds > 600) {
      throw ArgumentError('lease_seconds must be between 15 and 600');
    }
    final now = _readDateTimeOrNull(input['now']) ?? context.effectiveNow;
    final nowIso = now.toUtc().toIso8601String();
    final leaseUntil = now
        .toUtc()
        .add(Duration(seconds: leaseSeconds))
        .toIso8601String();
    return LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final rows = await handle.getAll(
        '${_reminderSelectSql()} WHERE r.user_id = ? AND r.target_type = ? '
        'AND r.reminder_status IN (?, ?) AND r.remind_at <= ? '
        'AND r.attempt_count < r.max_attempts '
        'AND (r.next_attempt_at IS NULL OR r.next_attempt_at <= ?) '
        'AND (r.lease_until IS NULL OR r.lease_until <= ?) '
        'AND t.status = ? AND t.task_status IN (?, ?) '
        'ORDER BY r.remind_at ASC, r.created_at ASC LIMIT ?',
        [
          context.userId,
          'task',
          'pending',
          'failed',
          nowIso,
          nowIso,
          nowIso,
          'active',
          'todo',
          'doing',
          limit,
        ],
      );
      final claimed = <LocalReminderRecord>[];
      for (final row in rows) {
        final old = _reminderFromRow(row);
        final dispatchToken = policy.nextEntityId('reminder_claim');
        await handle.execute(
          'UPDATE reminders SET reminder_status = ?, attempt_count = attempt_count + 1, '
          'last_attempt_at = ?, next_attempt_at = NULL, dispatch_token = ?, lease_until = ?, '
          'revision = revision + 1, updated_at = ? WHERE id = ? AND user_id = ? '
          'AND reminder_status IN (?, ?) AND (lease_until IS NULL OR lease_until <= ?)',
          [
            'pending',
            nowIso,
            dispatchToken,
            leaseUntil,
            nowIso,
            old.id,
            context.userId,
            'pending',
            'failed',
            nowIso,
          ],
        );
        final updatedRow = await _findReminderRow(handle, old.id, context.userId);
        if (updatedRow == null || updatedRow['dispatch_token'] != dispatchToken) {
          continue;
        }
        final updated = _reminderFromRow(updatedRow);
        await _writeReminderAudit(
          auditLogWriter,
          handle,
          context: context,
          action: 'reminder.dispatch.claim',
          before: old,
          after: updated,
        );
        claimed.add(updated);
      }
      return claimed;
    });
  }

  Future<LocalReminderRecord> markTaskReminderDelivered(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final reminderId = _requiredReminderId(input);
    final dispatchToken = _requiredDispatchToken(input);
    return LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final row = await _findReminderRow(handle, reminderId, context.userId);
      if (row == null) throw StateError('Reminder not found: $reminderId');
      final old = _reminderFromRow(row);
      if (old.status == 'delivered') return old;
      _requireReminderClaim(old, dispatchToken);
      final now = context.effectiveNow.toUtc().toIso8601String();
      await handle.execute(
        'UPDATE reminders SET reminder_status = ?, delivered_at = ?, failed_at = NULL, '
        'cancelled_at = NULL, last_error = NULL, external_id = coalesce(?, external_id), '
        'dispatch_token = NULL, lease_until = NULL, next_attempt_at = NULL, '
        'revision = revision + 1, updated_at = ? WHERE id = ? AND user_id = ?',
        [
          'delivered',
          now,
          input['external_id'] as String?,
          now,
          reminderId,
          context.userId,
        ],
      );
      final updated = _reminderFromRow(
        (await _findReminderRow(handle, reminderId, context.userId))!,
      );
      await _writeReminderAudit(
        auditLogWriter,
        handle,
        context: context,
        action: 'reminder.delivered',
        before: old,
        after: updated,
      );
      return updated;
    });
  }

  Future<LocalReminderRecord> markTaskReminderFailed(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final reminderId = _requiredReminderId(input);
    final dispatchToken = _requiredDispatchToken(input);
    final error = (input['error'] as String? ?? '').trim();
    if (error.isEmpty) throw ArgumentError('error is required');
    return LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final row = await _findReminderRow(handle, reminderId, context.userId);
      if (row == null) throw StateError('Reminder not found: $reminderId');
      final old = _reminderFromRow(row);
      _requireReminderClaim(old, dispatchToken);
      final failedAt = context.effectiveNow.toUtc();
      final retryAfterSeconds = input['retry_after_seconds'] as int?;
      if (retryAfterSeconds != null &&
          (retryAfterSeconds < 0 || retryAfterSeconds > 86400)) {
        throw ArgumentError('retry_after_seconds must be between 0 and 86400');
      }
      final nextAttemptAt = old.attemptCount >= old.maxAttempts
          ? null
          : failedAt.add(
              Duration(
                seconds: retryAfterSeconds ??
                    _retryDelaySeconds(old.attemptCount),
              ),
            );
      final failedAtIso = failedAt.toIso8601String();
      await handle.execute(
        'UPDATE reminders SET reminder_status = ?, failed_at = ?, last_error = ?, '
        'next_attempt_at = ?, dispatch_token = NULL, lease_until = NULL, '
        'revision = revision + 1, updated_at = ? WHERE id = ? AND user_id = ?',
        [
          'failed',
          failedAtIso,
          error.length > 4096 ? error.substring(0, 4096) : error,
          nextAttemptAt?.toIso8601String(),
          failedAtIso,
          reminderId,
          context.userId,
        ],
      );
      final updated = _reminderFromRow(
        (await _findReminderRow(handle, reminderId, context.userId))!,
      );
      await _writeReminderAudit(
        auditLogWriter,
        handle,
        context: context,
        action: 'reminder.failed',
        before: old,
        after: updated,
      );
      return updated;
    });
  }

  Future<LocalReminderRecord> retryTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final reminderId = _requiredReminderId(input);
    final resetAttempts = input['reset_attempts'] as bool? ?? true;
    return LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final row = await _findReminderRow(handle, reminderId, context.userId);
      if (row == null) throw StateError('Reminder not found: $reminderId');
      final old = _reminderFromRow(row);
      if (old.status == 'pending') return old;
      if (old.status != 'failed') {
        throw StateError(
          'Reminder $reminderId cannot retry from ${old.status}',
        );
      }
      final now = context.effectiveNow.toUtc().toIso8601String();
      await handle.execute(
        'UPDATE reminders SET reminder_status = ?, attempt_count = ?, '
        'next_attempt_at = ?, failed_at = NULL, last_error = NULL, '
        'dispatch_token = NULL, lease_until = NULL, revision = revision + 1, '
        'updated_at = ? WHERE id = ? AND user_id = ?',
        [
          'pending',
          resetAttempts ? 0 : old.attemptCount,
          now,
          now,
          reminderId,
          context.userId,
        ],
      );
      final updated = _reminderFromRow(
        (await _findReminderRow(handle, reminderId, context.userId))!,
      );
      await _writeReminderAudit(
        auditLogWriter,
        handle,
        context: context,
        action: 'reminder.retry',
        before: old,
        after: updated,
      );
      return updated;
    });
  }

  Future<LocalReminderRecord> cancelTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final reminderId = _requiredReminderId(input);
    return LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final row = await _findReminderRow(handle, reminderId, context.userId);
      if (row == null) throw StateError('Reminder not found: $reminderId');
      final old = _reminderFromRow(row);
      if (old.status == 'cancelled') return old;
      if (old.status == 'delivered') {
        throw StateError('Delivered reminder $reminderId cannot be cancelled');
      }
      final now = context.effectiveNow.toUtc().toIso8601String();
      await handle.execute(
        'UPDATE reminders SET reminder_status = ?, cancelled_at = ?, '
        'next_attempt_at = NULL, dispatch_token = NULL, lease_until = NULL, '
        'revision = revision + 1, updated_at = ? WHERE id = ? AND user_id = ?',
        ['cancelled', now, now, reminderId, context.userId],
      );
      final updated = _reminderFromRow(
        (await _findReminderRow(handle, reminderId, context.userId))!,
      );
      await _writeReminderAudit(
        auditLogWriter,
        handle,
        context: context,
        action: 'reminder.cancelled',
        before: old,
        after: updated,
      );
      return updated;
    });
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

}
