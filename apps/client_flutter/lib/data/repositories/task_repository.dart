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

  Future<PagedResult<Task>> listPage({
    int limit = 20,
    int offset = 0,
    String? taskStatus,
    bool overdue = false,
    bool today = false,
  }) async {
    if (_useLocalCore) {
      final records = await localCore!.listTasks({
        'task_status': taskStatus,
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
  }) async {
    final page = await listPage(
      limit: limit,
      offset: offset,
      taskStatus: taskStatus,
      overdue: overdue,
      today: today,
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
}
