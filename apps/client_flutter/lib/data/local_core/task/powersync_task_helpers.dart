part of 'powersync_task_store.dart';

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
  LocalCoreAuditLogWriter auditLogWriter,
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
  LocalCoreAuditLogWriter auditLogWriter,
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
      auditLogWriter,
      handle,
      context: context,
      action: 'reminder.cancelled',
      before: old,
      after: updated,
    );
  }
}

Future<LocalTaskRecord?> _findTaskById(
  SyncService syncService,
  String taskId,
) async {
  final row = await syncService.db.getOptional(
    'SELECT id, title, description, due_at, remind_at, priority, task_status, completed_at, status, revision, created_at, updated_at '
    'FROM tasks WHERE id = ? AND status = ?',
    [taskId, 'active'],
  );
  return row == null ? null : LocalTaskMapper.fromRow(row);
}

Future<Map<String, LocalTaskReminderStrategy>> _strategyMap(
  SyncService syncService,
) async {
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

Future<List<Map<String, Object?>>> _listRows(
  SyncService syncService, {
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

Future<void> _upsertTaskReminderRecord(
  SyncService syncService,
  LocalCoreWritePolicy policy,
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
