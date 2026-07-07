import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';
import 'package:client_flutter/domain/entities/task.dart';

class TaskRepository {
  final ApiClient api;
  final LocalCoreBridge? localCore;
  final LiflyDataMode dataMode;

  TaskRepository(this.api, {this.localCore, this.dataMode = LiflyDataMode.api});

  bool get _useLocalCore =>
      dataMode == LiflyDataMode.local && localCore != null;

  bool get _hasLocalCore => localCore != null;

  Future<PagedResult<Task>> listPage({
    int limit = 20,
    int offset = 0,
    String? taskStatus,
    bool overdue = false,
    bool today = false,
    String group = 'all',
  }) async {
    if (_useLocalCore) {
      final records = await localCore!.listTasks({
        'task_status': taskStatus,
        'group': group,
        'limit': limit + offset,
      }, LocalCoreContext.flutterUser());
      final pageItems = records
          .skip(offset)
          .take(limit)
          .map(_taskFromLocal)
          .toList(growable: false);
      return PagedResult(
        items: pageItems,
        total: records.length,
        limit: limit,
        offset: offset,
      );
    }

    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (taskStatus != null && taskStatus.isNotEmpty) {
      params['task_status'] = taskStatus;
    }
    if (overdue) params['overdue'] = true;
    if (today) params['today'] = true;
    if (group != 'all') params['group'] = group;

    final res = await api.get('/tasks', params: params);
    return PagedResult.fromData(
      res['data'] as Map<String, dynamic>,
      Task.fromJson,
    );
  }

  Future<List<Task>> list({
    int limit = 20,
    int offset = 0,
    String? taskStatus,
    bool overdue = false,
    bool today = false,
    String group = 'all',
  }) async {
    final page = await listPage(
      limit: limit,
      offset: offset,
      taskStatus: taskStatus,
      overdue: overdue,
      today: today,
      group: group,
    );
    return page.items;
  }

  Future<Task> get(String id) async {
    if (_useLocalCore) {
      final records = await localCore!.listTasks({
        'limit': 100,
      }, LocalCoreContext.flutterUser());
      for (final record in records) {
        if (record.id == id) return _taskFromLocal(record);
      }
      throw StateError('Task not found: $id');
    }

    final res = await api.get('/tasks/$id');
    return Task.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Task> create(Map<String, dynamic> data) async {
    if (_useLocalCore) {
      final record = await localCore!.createTask(
        data,
        LocalCoreContext.flutterUser(),
      );
      return _taskFromLocal(record);
    }

    final res = await api.post('/tasks', data: data);
    return Task.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Task> update(String id, Map<String, dynamic> data) async {
    if (_useLocalCore) {
      final record = await localCore!.updateTask({
        ...data,
        'task_id': id,
      }, LocalCoreContext.flutterUser());
      return _taskFromLocal(record);
    }

    final res = await api.put('/tasks/$id', data: data);
    return Task.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Task> complete(String id) async {
    if (_useLocalCore) {
      final record = await localCore!.completeTask({
        'task_id': id,
      }, LocalCoreContext.flutterUser());
      return _taskFromLocal(record);
    }

    final res = await api.post('/tasks/$id/complete', data: const {});
    return Task.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>?> reminderStrategy(String taskId) async {
    if (dataMode == LiflyDataMode.local) {
      final item = await localCore!.getTaskReminderStrategy({
        'task_id': taskId,
      }, LocalCoreContext.flutterUser());
      return item == null ? null : _strategyToMap(item);
    }

    try {
      final res = await api.get('/tasks/$taskId/reminder-strategy');
      return res['data'] == null
          ? null
          : Map<String, dynamic>.from(res['data'] as Map);
    } catch (error) {
      if (_hasLocalCore) {
        final item = await localCore!.getTaskReminderStrategy({
          'task_id': taskId,
        }, LocalCoreContext.flutterUser());
        return item == null ? null : _strategyToMap(item);
      }
      throw StateError('Task reminder strategy unavailable: $error');
    }
  }

  Future<Map<String, dynamic>?> generateReminderStrategy(
    String taskId, {
    bool replaceSuggested = true,
  }) async {
    final data = {'replace_suggested': replaceSuggested};
    if (dataMode == LiflyDataMode.local) {
      final item = await localCore!.generateTaskReminderStrategy({
        ...data,
        'task_id': taskId,
      }, LocalCoreContext.flutterUser());
      return item == null ? null : _strategyToMap(item);
    }

    final res = await api.post(
      '/tasks/$taskId/reminder-strategy/generate',
      data: data,
    );
    return res['data'] == null
        ? null
        : Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<Map<String, dynamic>> confirmReminderStrategy(
    String taskId,
    Map<String, dynamic> data,
  ) async {
    if (dataMode == LiflyDataMode.local) {
      final item = await localCore!.confirmTaskReminderStrategy({
        ...data,
        'task_id': taskId,
      }, LocalCoreContext.flutterUser());
      return _strategyToMap(item);
    }

    final res = await api.post(
      '/tasks/$taskId/reminder-strategy/confirm',
      data: data,
    );
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<Map<String, dynamic>> dismissReminderStrategy(
    String taskId,
    Map<String, dynamic> data,
  ) async {
    if (dataMode == LiflyDataMode.local) {
      final item = await localCore!.dismissTaskReminderStrategy({
        ...data,
        'task_id': taskId,
      }, LocalCoreContext.flutterUser());
      return _strategyToMap(item);
    }

    final res = await api.post(
      '/tasks/$taskId/reminder-strategy/dismiss',
      data: data,
    );
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> reminders({
    String status = 'pending',
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final items = await localCore!.listTaskReminders({
        'status': status,
      }, LocalCoreContext.flutterUser());
      return items.map(_reminderToMap).toList(growable: false);
    }

    final res = await api.get('/tasks/reminders', params: {'reminder_status': status});
    final items = res['data'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<void> delete(String id) async {
    if (_useLocalCore) {
      await localCore!.deleteTask({
        'task_id': id,
      }, LocalCoreContext.flutterUser());
      return;
    }

    await api.delete('/tasks/$id');
  }

  Task _taskFromLocal(LocalTaskRecord record) {
    return Task(
      id: record.id,
      title: record.title,
      description: record.description,
      dueAt: record.dueAt,
      remindAt: record.remindAt,
      priority: record.priority,
      taskStatus: record.taskStatus,
      completedAt: record.completedAt,
      createdAt: record.createdAt,
    );
  }

  Map<String, dynamic> _reminderToMap(LocalReminderRecord item) {
    return {
      'id': item.id,
      'target_type': item.targetType,
      'target_id': item.targetId,
      'remind_at': item.remindAt.toIso8601String(),
      'channel': item.channel,
      'reminder_status': item.status,
      'created_at': item.createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _strategyToMap(LocalTaskReminderStrategy item) {
    return {
      'id': item.id,
      'task_id': item.taskId,
      'warning_level': item.warningLevel,
      'warning_reason': item.warningReason,
      'preparation_window_days': item.preparationWindowDays,
      'ai_suggested_remind_at': item.aiSuggestedRemindAt?.toIso8601String(),
      'strategy_status': item.strategyStatus,
      'source': item.source,
      'confirmed_at': item.confirmedAt?.toIso8601String(),
      'dismissed_at': item.dismissedAt?.toIso8601String(),
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
    };
  }
}
