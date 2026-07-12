part of '../fake_local_core_bridge.dart';

mixin _FakeTaskStore on _FakeLocalCoreState {
  @override
  Future<LocalTaskRecord> createTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final now = context.effectiveNow;
    final task = LocalTaskRecord(
      id: _nextStableId('task'),
      title: input['title'] as String? ?? '',
      description: input['description'] as String?,
      dueAt: DateTime.tryParse(input['due_at'] as String? ?? ''),
      remindAt: DateTime.tryParse(input['remind_at'] as String? ?? ''),
      priority: input['priority'] as String? ?? 'normal',
      taskStatus: 'todo',
      completedAt: null,
      status: 'active',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    _tasks.insert(0, task);
    await generateTaskReminderStrategy({'task_id': task.id}, context);
    return task;
  }

  @override
  Future<List<LocalTaskRecord>> listTasks(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskStatus = input['task_status'] as String?;
    final group = input['group'] as String? ?? 'all';
    final limit = input['limit'] as int? ?? 20;
    return _tasks
        .where((task) => task.status == 'active')
        .where((task) => taskStatus == null || task.taskStatus == taskStatus)
        .where((task) => _matchesTaskGroup(task, group, context.effectiveNow))
        .take(limit)
        .toList();
  }

  @override
  Future<LocalTaskRecord> completeTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String?;
    final index = _tasks.indexWhere(
      (task) => task.id == taskId && task.status == 'active',
    );
    if (index < 0) throw StateError('Task not found: $taskId');

    final old = _tasks[index];
    final now = context.effectiveNow;
    final updated = LocalTaskRecord(
      id: old.id,
      title: old.title,
      description: old.description,
      dueAt: old.dueAt,
      remindAt: old.remindAt,
      priority: old.priority,
      taskStatus: 'done',
      completedAt: now,
      status: old.status,
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: now,
    );
    _tasks[index] = updated;
    _cancelFakeReminders(updated.id, context);
    return updated;
  }

  @override
  Future<LocalTaskRecord> updateTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    final index = _tasks.indexWhere(
      (task) => task.id == taskId && task.status == 'active',
    );
    if (index < 0) throw StateError('Task not found: $taskId');

    final old = _tasks[index];
    final updated = LocalTaskRecord(
      id: old.id,
      title: input['title'] as String? ?? old.title,
      description: input.containsKey('description')
          ? input['description'] as String?
          : old.description,
      dueAt: input.containsKey('due_at')
          ? DateTime.tryParse(input['due_at'] as String? ?? '')
          : old.dueAt,
      remindAt: input.containsKey('remind_at')
          ? DateTime.tryParse(input['remind_at'] as String? ?? '')
          : old.remindAt,
      priority: input['priority'] as String? ?? old.priority,
      taskStatus: input['task_status'] as String? ?? old.taskStatus,
      completedAt: old.completedAt,
      status: old.status,
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _tasks[index] = updated;
    if (updated.taskStatus == 'done' || updated.taskStatus == 'cancelled') {
      _cancelFakeReminders(updated.id, context);
    }
    return updated;
  }

  @override
  Future<LocalTaskRecord> deleteTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    final index = _tasks.indexWhere(
      (task) => task.id == taskId && task.status == 'active',
    );
    if (index < 0) throw StateError('Task not found: $taskId');

    final old = _tasks[index];
    final updated = LocalTaskRecord(
      id: old.id,
      title: old.title,
      description: old.description,
      dueAt: old.dueAt,
      remindAt: old.remindAt,
      priority: old.priority,
      taskStatus: old.taskStatus,
      completedAt: old.completedAt,
      status: input['status'] as String? ?? 'deleted',
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _tasks[index] = updated;
    _cancelFakeReminders(updated.id, context);
    return updated;
  }

  @override
  Future<LocalTaskReminderStrategy?> getTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    return _taskReminderStrategies
        .cast<LocalTaskReminderStrategy?>()
        .firstWhere(
          (item) =>
              item?.taskId == taskId && item?.strategyStatus != 'dismissed',
          orElse: () => null,
        );
  }

  @override
  Future<LocalTaskReminderStrategy?> generateTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    final task = _tasks.firstWhere(
      (item) => item.id == taskId && item.status == 'active',
    );
    final existing = await getTaskReminderStrategy({'task_id': task.id}, context);
    if (existing?.strategyStatus == 'confirmed') return existing;
    _taskReminderStrategies.removeWhere(
      (item) =>
          item.taskId == task.id &&
          item.source == 'ai' &&
          item.strategyStatus == 'suggested',
    );
    final suggestion = const LocalTaskReminderStrategyEngine().suggest(
      task,
      now: context.effectiveNow,
    );
    if (suggestion == null) return null;
    final now = context.effectiveNow;
    final item = LocalTaskReminderStrategy(
      id: _nextStableId('task_strategy'),
      taskId: task.id,
      warningLevel: suggestion.warningLevel,
      warningReason: suggestion.warningReason,
      preparationWindowDays: suggestion.preparationWindowDays,
      aiSuggestedRemindAt: suggestion.aiSuggestedRemindAt,
      strategyStatus: 'suggested',
      source: 'ai',
      createdAt: now,
      updatedAt: now,
      confirmedAt: null,
      dismissedAt: null,
    );
    _taskReminderStrategies.add(item);
    return item;
  }

  @override
  Future<LocalTaskReminderStrategy> confirmTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final item = _upsertTaskReminderStrategy(input, context, 'confirmed');
    final remindAt = item.aiSuggestedRemindAt;
    if (remindAt != null) {
      await updateTask({
        'task_id': item.taskId,
        'remind_at': remindAt.toIso8601String(),
      }, context);
      _upsertFakeReminder(item, context);
    }
    return item;
  }

  @override
  Future<LocalTaskReminderStrategy> dismissTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final strategy = _upsertTaskReminderStrategy(input, context, 'dismissed');
    _cancelFakeReminders(strategy.taskId, context);
    return strategy;
  }

  @override
  Future<List<LocalReminderRecord>> listTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final status = input.containsKey('status')
        ? input['status'] as String?
        : input['reminder_status'] as String? ?? 'pending';
    final dueBefore = DateTime.tryParse(input['due_before'] as String? ?? '');
    final limit = input['limit'] as int? ?? 100;
    final items = _reminders
        .where((item) => item.targetType == 'task')
        .where((item) => status == null || item.status == status)
        .where(
          (item) => dueBefore == null || !item.remindAt.isAfter(dueBefore),
        )
        .toList()
      ..sort((a, b) => a.remindAt.compareTo(b.remindAt));
    return items.take(limit).toList(growable: false);
  }

  @override
  Future<List<LocalReminderRecord>> claimDueTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final now =
        DateTime.tryParse(input['now'] as String? ?? '') ?? context.effectiveNow;
    final limit = input['limit'] as int? ?? 20;
    final leaseSeconds = input['lease_seconds'] as int? ?? 120;
    final candidates = _reminders
        .asMap()
        .entries
        .where(
          (entry) =>
              const {'pending', 'failed'}.contains(entry.value.status) &&
              !entry.value.remindAt.isAfter(now) &&
              entry.value.attemptCount < entry.value.maxAttempts &&
              (entry.value.nextAttemptAt == null ||
                  !entry.value.nextAttemptAt!.isAfter(now)) &&
              (entry.value.leaseUntil == null ||
                  !entry.value.leaseUntil!.isAfter(now)),
        )
        .take(limit)
        .toList();
    final claimed = <LocalReminderRecord>[];
    for (final entry in candidates) {
      final old = entry.value;
      final task = _tasks.cast<LocalTaskRecord?>().firstWhere(
            (item) =>
                item?.id == old.targetId &&
                item?.status == 'active' &&
                const {'todo', 'doing'}.contains(item?.taskStatus),
            orElse: () => null,
          );
      if (task == null) continue;
      final updated = _copyFakeReminder(
        old,
        status: 'pending',
        attemptCount: old.attemptCount + 1,
        nextAttemptAt: null,
        lastAttemptAt: now,
        dispatchToken: _nextStableId('reminder_claim'),
        leaseUntil: now.add(Duration(seconds: leaseSeconds)),
        revision: old.revision + 1,
        updatedAt: now,
        title: task.title,
        body: task.description,
      );
      _reminders[entry.key] = updated;
      claimed.add(updated);
    }
    return claimed;
  }

  @override
  Future<LocalReminderRecord> markTaskReminderDelivered(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final index = _fakeReminderIndex(input);
    final old = _reminders[index];
    if (old.status == 'delivered') return old;
    _requireFakeClaim(old, input['dispatch_token'] as String?);
    final updated = _copyFakeReminder(
      old,
      status: 'delivered',
      deliveredAt: context.effectiveNow,
      failedAt: null,
      cancelledAt: null,
      lastError: null,
      externalId: input['external_id'] as String? ?? old.externalId,
      dispatchToken: null,
      leaseUntil: null,
      nextAttemptAt: null,
      revision: old.revision + 1,
      updatedAt: context.effectiveNow,
    );
    _reminders[index] = updated;
    return updated;
  }

  @override
  Future<LocalReminderRecord> markTaskReminderFailed(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final index = _fakeReminderIndex(input);
    final old = _reminders[index];
    _requireFakeClaim(old, input['dispatch_token'] as String?);
    final error = (input['error'] as String? ?? '').trim();
    if (error.isEmpty) throw ArgumentError('error is required');
    final now = context.effectiveNow;
    final retryAfterSeconds =
        input['retry_after_seconds'] as int? ??
        _fakeRetryDelaySeconds(old.attemptCount);
    final updated = _copyFakeReminder(
      old,
      status: 'failed',
      failedAt: now,
      lastError: error,
      nextAttemptAt: old.attemptCount >= old.maxAttempts
          ? null
          : now.add(Duration(seconds: retryAfterSeconds)),
      dispatchToken: null,
      leaseUntil: null,
      revision: old.revision + 1,
      updatedAt: now,
    );
    _reminders[index] = updated;
    return updated;
  }

  @override
  Future<LocalReminderRecord> retryTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final index = _fakeReminderIndex(input);
    final old = _reminders[index];
    if (old.status == 'pending') return old;
    if (old.status != 'failed') {
      throw StateError('Reminder ${old.id} cannot retry from ${old.status}');
    }
    final updated = _copyFakeReminder(
      old,
      status: 'pending',
      attemptCount: (input['reset_attempts'] as bool? ?? true)
          ? 0
          : old.attemptCount,
      nextAttemptAt: context.effectiveNow,
      failedAt: null,
      lastError: null,
      dispatchToken: null,
      leaseUntil: null,
      revision: old.revision + 1,
      updatedAt: context.effectiveNow,
    );
    _reminders[index] = updated;
    return updated;
  }

  @override
  Future<LocalReminderRecord> cancelTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final index = _fakeReminderIndex(input);
    final old = _reminders[index];
    if (old.status == 'cancelled') return old;
    if (old.status == 'delivered') {
      throw StateError('Delivered reminder ${old.id} cannot be cancelled');
    }
    final updated = _copyFakeReminder(
      old,
      status: 'cancelled',
      cancelledAt: context.effectiveNow,
      nextAttemptAt: null,
      dispatchToken: null,
      leaseUntil: null,
      revision: old.revision + 1,
      updatedAt: context.effectiveNow,
    );
    _reminders[index] = updated;
    return updated;
  }

  void _upsertFakeReminder(
    LocalTaskReminderStrategy strategy,
    LocalCoreContext context,
  ) {
    final remindAt = strategy.aiSuggestedRemindAt;
    if (remindAt == null) return;
    final index = _reminders.indexWhere(
      (item) =>
          item.targetType == 'task' &&
          item.targetId == strategy.taskId &&
          const {'pending', 'failed'}.contains(item.status),
    );
    final old = index < 0 ? null : _reminders[index];
    final task = _tasks.cast<LocalTaskRecord?>().firstWhere(
          (item) => item?.id == strategy.taskId,
          orElse: () => null,
        );
    final item = LocalReminderRecord(
      id: old?.id ?? _nextStableId('reminder'),
      targetType: 'task',
      targetId: strategy.taskId,
      remindAt: remindAt,
      channel: 'app',
      status: 'pending',
      attemptCount: 0,
      maxAttempts: old?.maxAttempts ?? 3,
      nextAttemptAt: remindAt,
      lastAttemptAt: old?.lastAttemptAt,
      deliveredAt: null,
      failedAt: null,
      cancelledAt: null,
      lastError: null,
      externalId: old?.externalId,
      dispatchToken: null,
      leaseUntil: null,
      revision: (old?.revision ?? 0) + 1,
      createdAt: old?.createdAt ?? context.effectiveNow,
      updatedAt: context.effectiveNow,
      title: task?.title,
      body: task?.description,
    );
    if (index < 0) {
      _reminders.add(item);
    } else {
      _reminders[index] = item;
    }
  }

  LocalTaskReminderStrategy _upsertTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
    String status,
  ) {
    final strategyId =
        input['strategy_id'] as String? ?? input['id'] as String?;
    final taskId = input['task_id'] as String?;
    final index = strategyId == null
        ? _taskReminderStrategies.indexWhere((item) => item.taskId == taskId)
        : _taskReminderStrategies.indexWhere((item) => item.id == strategyId);
    final old = index < 0 ? null : _taskReminderStrategies[index];
    if (old == null && taskId == null) {
      throw ArgumentError(
        'task_id is required when strategy_id is not provided',
      );
    }
    final now = context.effectiveNow;
    final item = LocalTaskReminderStrategy(
      id: old?.id ?? _nextStableId('task_strategy'),
      taskId: old?.taskId ?? taskId!,
      warningLevel:
          input['warning_level'] as String? ?? old?.warningLevel ?? 'normal',
      warningReason: input['warning_reason'] as String? ?? old?.warningReason,
      preparationWindowDays:
          input['preparation_window_days'] as int? ??
          old?.preparationWindowDays,
      aiSuggestedRemindAt: input.containsKey('ai_suggested_remind_at')
          ? DateTime.tryParse(input['ai_suggested_remind_at'] as String? ?? '')
          : old?.aiSuggestedRemindAt,
      strategyStatus: status,
      source: input['source'] as String? ?? old?.source ?? 'user',
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      confirmedAt: status == 'confirmed' ? now : old?.confirmedAt,
      dismissedAt: status == 'dismissed' ? now : old?.dismissedAt,
    );
    if (index < 0) {
      _taskReminderStrategies.add(item);
    } else {
      _taskReminderStrategies[index] = item;
    }
    return item;
  }

  bool _matchesTaskGroup(LocalTaskRecord task, String group, DateTime now) {
    if (group == 'all') return true;
    if (task.taskStatus != 'todo' && task.taskStatus != 'doing') return false;
    final dueAt = task.dueAt;
    final strategy = _taskReminderStrategies
        .cast<LocalTaskReminderStrategy?>()
        .firstWhere(
          (item) =>
              item?.taskId == task.id && item?.strategyStatus != 'dismissed',
          orElse: () => null,
        );
    if (group == 'urgent') {
      return strategy?.warningLevel == 'critical' ||
          task.priority == 'urgent' ||
          (dueAt != null && dueAt.isBefore(now));
    }
    if (group == 'warning') {
      final warningDue =
          dueAt != null &&
          dueAt.isAfter(now) &&
          dueAt.difference(now).inDays <= 3;
      return strategy?.warningLevel == 'warning' ||
          task.priority == 'high' ||
          warningDue;
    }
    if (group == 'today') {
      if (dueAt == null) return false;
      final localDue = dueAt.toUtc();
      final localNow = now.toUtc();
      return localDue.year == localNow.year &&
          localDue.month == localNow.month &&
          localDue.day == localNow.day;
    }
    return true;
  }

  int _fakeReminderIndex(Map<String, Object?> input) {
    final reminderId = input['reminder_id'] as String? ?? input['id'] as String?;
    final index = _reminders.indexWhere((item) => item.id == reminderId);
    if (index < 0) throw StateError('Reminder not found: $reminderId');
    return index;
  }

  void _requireFakeClaim(
    LocalReminderRecord reminder,
    String? dispatchToken,
  ) {
    if (reminder.status == 'delivered' || reminder.status == 'cancelled') {
      throw StateError(
        'Reminder ${reminder.id} cannot transition from ${reminder.status}',
      );
    }
    if (dispatchToken == null || reminder.dispatchToken != dispatchToken) {
      throw StateError('Reminder ${reminder.id} dispatch token is stale');
    }
  }

  int _fakeRetryDelaySeconds(int attemptCount) {
    final exponent = attemptCount <= 1 ? 0 : attemptCount - 1;
    final clamped = exponent > 5 ? 5 : exponent;
    final seconds = 60 * (1 << clamped);
    return seconds > 3600 ? 3600 : seconds;
  }

  void _cancelFakeReminders(String taskId, LocalCoreContext context) {
    for (var index = 0; index < _reminders.length; index += 1) {
      final old = _reminders[index];
      if (old.targetType != 'task' ||
          old.targetId != taskId ||
          !const {'pending', 'failed'}.contains(old.status)) {
        continue;
      }
      _reminders[index] = _copyFakeReminder(
        old,
        status: 'cancelled',
        cancelledAt: context.effectiveNow,
        nextAttemptAt: null,
        dispatchToken: null,
        leaseUntil: null,
        revision: old.revision + 1,
        updatedAt: context.effectiveNow,
      );
    }
  }

  LocalReminderRecord _copyFakeReminder(
    LocalReminderRecord old, {
    String? status,
    int? attemptCount,
    int? maxAttempts,
    Object? nextAttemptAt = _fakeReminderUnchanged,
    Object? lastAttemptAt = _fakeReminderUnchanged,
    Object? deliveredAt = _fakeReminderUnchanged,
    Object? failedAt = _fakeReminderUnchanged,
    Object? cancelledAt = _fakeReminderUnchanged,
    Object? lastError = _fakeReminderUnchanged,
    Object? externalId = _fakeReminderUnchanged,
    Object? dispatchToken = _fakeReminderUnchanged,
    Object? leaseUntil = _fakeReminderUnchanged,
    int? revision,
    DateTime? updatedAt,
    Object? title = _fakeReminderUnchanged,
    Object? body = _fakeReminderUnchanged,
  }) {
    return LocalReminderRecord(
      id: old.id,
      targetType: old.targetType,
      targetId: old.targetId,
      remindAt: old.remindAt,
      channel: old.channel,
      status: status ?? old.status,
      attemptCount: attemptCount ?? old.attemptCount,
      maxAttempts: maxAttempts ?? old.maxAttempts,
      nextAttemptAt: identical(nextAttemptAt, _fakeReminderUnchanged)
          ? old.nextAttemptAt
          : nextAttemptAt as DateTime?,
      lastAttemptAt: identical(lastAttemptAt, _fakeReminderUnchanged)
          ? old.lastAttemptAt
          : lastAttemptAt as DateTime?,
      deliveredAt: identical(deliveredAt, _fakeReminderUnchanged)
          ? old.deliveredAt
          : deliveredAt as DateTime?,
      failedAt: identical(failedAt, _fakeReminderUnchanged)
          ? old.failedAt
          : failedAt as DateTime?,
      cancelledAt: identical(cancelledAt, _fakeReminderUnchanged)
          ? old.cancelledAt
          : cancelledAt as DateTime?,
      lastError: identical(lastError, _fakeReminderUnchanged)
          ? old.lastError
          : lastError as String?,
      externalId: identical(externalId, _fakeReminderUnchanged)
          ? old.externalId
          : externalId as String?,
      dispatchToken: identical(dispatchToken, _fakeReminderUnchanged)
          ? old.dispatchToken
          : dispatchToken as String?,
      leaseUntil: identical(leaseUntil, _fakeReminderUnchanged)
          ? old.leaseUntil
          : leaseUntil as DateTime?,
      revision: revision ?? old.revision,
      createdAt: old.createdAt,
      updatedAt: updatedAt ?? old.updatedAt,
      title: identical(title, _fakeReminderUnchanged)
          ? old.title
          : title as String?,
      body: identical(body, _fakeReminderUnchanged)
          ? old.body
          : body as String?,
    );
  }
}
