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
      await _cancelActiveTaskReminders(handle, deletedTask.id, context);
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
      await _cancelActiveTaskReminders(handle, completedTask.id, context);
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
        await _cancelActiveTaskReminders(handle, updatedTask.id, context);
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
    final strategy = await _upsertStrategy(input, context, 'dismissed');
    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      await _cancelActiveTaskReminders(handle, strategy.taskId, context);
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

  Future<void> _upsertTaskReminderRecord(
    LocalTaskReminderStrategy strategy,
    LocalCoreContext context,
  ) async {
    final remindAt = strategy.aiSuggestedRemindAt;
    if (remindAt == null) return;
    await syncService.ensureInitialized();
    final now = context.effectiveNow.toUtc().toIso8601String();
    final existing = await syncService.db.getOptional(
      'SELECT id FROM reminders WHERE user_id = ? AND target_type = ? AND target_id = ? '
      'AND channel = ? AND reminder_status IN (?, ?) ORDER BY created_at DESC LIMIT 1',
      [context.userId, 'task', strategy.taskId, 'app', 'pending', 'failed'],
    );
    if (existing == null) {
      await syncService.db.execute(
        'INSERT INTO reminders(id, user_id, target_type, target_id, remind_at, channel, '
        'reminder_status, attempt_count, max_attempts, next_attempt_at, revision, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          policy.nextEntityId('reminder'),
          context.userId,
          'task',
          strategy.taskId,
          remindAt.toIso8601String(),
          'app',
          'pending',
          0,
          3,
          remindAt.toIso8601String(),
          1,
          now,
          now,
        ],
      );
    } else {
      await syncService.db.execute(
        'UPDATE reminders SET remind_at = ?, reminder_status = ?, attempt_count = 0, '
        'next_attempt_at = ?, failed_at = NULL, last_error = NULL, '
        'dispatch_token = NULL, lease_until = NULL, revision = revision + 1, '
        'updated_at = ? WHERE id = ?',
        [
          remindAt.toIso8601String(),
          'pending',
          remindAt.toIso8601String(),
          now,
          existing['id'],
        ],
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
      attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
      maxAttempts: (row['max_attempts'] as num?)?.toInt() ?? 3,
      nextAttemptAt: _readDateTimeOrNull(row['next_attempt_at']),
      lastAttemptAt: _readDateTimeOrNull(row['last_attempt_at']),
      deliveredAt: _readDateTimeOrNull(row['delivered_at']),
      failedAt: _readDateTimeOrNull(row['failed_at']),
      cancelledAt: _readDateTimeOrNull(row['cancelled_at']),
      lastError: row['last_error'] as String?,
      externalId: row['external_id'] as String?,
      dispatchToken: row['dispatch_token'] as String?,
      leaseUntil: _readDateTimeOrNull(row['lease_until']),
      revision: (row['revision'] as num?)?.toInt() ?? 1,
      createdAt: _readDateTime(row['created_at']),
      updatedAt: _readDateTime(row['updated_at'] ?? row['created_at']),
      title: row['task_title'] as String?,
      body: row['task_description'] as String?,
    );
  }

  String _reminderSelectSql() {
    return 'SELECT r.id, r.target_type, r.target_id, r.remind_at, r.channel, '
        'r.reminder_status, r.attempt_count, r.max_attempts, r.next_attempt_at, '
        'r.last_attempt_at, r.delivered_at, r.failed_at, r.cancelled_at, '
        'r.last_error, r.external_id, r.dispatch_token, r.lease_until, r.revision, '
        'r.created_at, r.updated_at, t.title AS task_title, '
        't.description AS task_description FROM reminders r '
        "LEFT JOIN tasks t ON t.id = r.target_id AND r.target_type = 'task'";
  }

  Future<Map<String, Object?>?> _findReminderRow(
    LocalCoreWriteHandle handle,
    String reminderId,
    String userId,
  ) {
    return handle.getOptional(
      '${_reminderSelectSql()} WHERE r.id = ? AND r.user_id = ?',
      [reminderId, userId],
    );
  }

  Future<void> _writeReminderAudit(
    LocalCoreWriteHandle handle, {
    required LocalCoreContext context,
    required String action,
    required LocalReminderRecord before,
    required LocalReminderRecord after,
  }) {
    return auditLogWriter.write(
      handle,
      LocalCoreAuditLogInput(
        context: context,
        action: action,
        entityType: 'reminder',
        entityId: after.id,
        beforeSnapshot: _reminderSnapshot(before),
        afterSnapshot: _reminderSnapshot(after),
      ),
    );
  }

  Map<String, Object?> _reminderSnapshot(LocalReminderRecord reminder) {
    return {
      'id': reminder.id,
      'target_type': reminder.targetType,
      'target_id': reminder.targetId,
      'remind_at': reminder.remindAt.toIso8601String(),
      'channel': reminder.channel,
      'reminder_status': reminder.status,
      'attempt_count': reminder.attemptCount,
      'max_attempts': reminder.maxAttempts,
      'next_attempt_at': reminder.nextAttemptAt?.toIso8601String(),
      'last_attempt_at': reminder.lastAttemptAt?.toIso8601String(),
      'delivered_at': reminder.deliveredAt?.toIso8601String(),
      'failed_at': reminder.failedAt?.toIso8601String(),
      'cancelled_at': reminder.cancelledAt?.toIso8601String(),
      'last_error': reminder.lastError,
      'external_id': reminder.externalId,
      'dispatch_token': reminder.dispatchToken,
      'lease_until': reminder.leaseUntil?.toIso8601String(),
      'revision': reminder.revision,
      'created_at': reminder.createdAt.toIso8601String(),
      'updated_at': reminder.updatedAt.toIso8601String(),
    };
  }

  String _requiredReminderId(Map<String, Object?> input) {
    final value = input['reminder_id'] as String? ?? input['id'] as String?;
    if (value == null || value.trim().isEmpty) {
      throw ArgumentError('reminder_id is required');
    }
    return value.trim();
  }

  String _requiredDispatchToken(Map<String, Object?> input) {
    final value = input['dispatch_token'] as String?;
    if (value == null || value.trim().isEmpty) {
      throw ArgumentError('dispatch_token is required');
    }
    return value.trim();
  }

  void _requireReminderClaim(
    LocalReminderRecord reminder,
    String dispatchToken,
  ) {
    if (reminder.status == 'delivered' || reminder.status == 'cancelled') {
      throw StateError(
        'Reminder ${reminder.id} cannot transition from ${reminder.status}',
      );
    }
    if (reminder.dispatchToken == null ||
        reminder.dispatchToken != dispatchToken) {
      throw StateError('Reminder ${reminder.id} dispatch token is stale');
    }
  }

  int _retryDelaySeconds(int attemptCount) {
    final exponent = attemptCount <= 1 ? 0 : attemptCount - 1;
    final clampedExponent = exponent > 5 ? 5 : exponent;
    final seconds = 60 * (1 << clampedExponent);
    return seconds > 3600 ? 3600 : seconds;
  }

  void _validateReminderStatus(String status) {
    if (!const {'pending', 'delivered', 'failed', 'cancelled'}.contains(status)) {
      throw ArgumentError('Unsupported reminder status: $status');
    }
  }

  Future<void> _cancelActiveTaskReminders(
    LocalCoreWriteHandle handle,
    String taskId,
    LocalCoreContext context,
  ) async {
    final rows = await handle.getAll(
      '${_reminderSelectSql()} WHERE r.user_id = ? AND r.target_type = ? '
      'AND r.target_id = ? AND r.reminder_status IN (?, ?)',
      [context.userId, 'task', taskId, 'pending', 'failed'],
    );
    final now = context.effectiveNow.toUtc().toIso8601String();
    for (final row in rows) {
      final old = _reminderFromRow(row);
      await handle.execute(
        'UPDATE reminders SET reminder_status = ?, cancelled_at = ?, '
        'next_attempt_at = NULL, dispatch_token = NULL, lease_until = NULL, '
        'revision = revision + 1, updated_at = ? WHERE id = ? AND user_id = ?',
        ['cancelled', now, now, old.id, context.userId],
      );
      final updated = _reminderFromRow(
        (await _findReminderRow(handle, old.id, context.userId))!,
      );
      await _writeReminderAudit(
        handle,
        context: context,
        action: 'reminder.cancelled',
        before: old,
        after: updated,
      );
    }
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
