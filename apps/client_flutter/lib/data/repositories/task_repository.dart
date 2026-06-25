import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';
import 'package:client_flutter/domain/entities/task.dart';

class TaskRepository {
  final ApiClient api;

  TaskRepository(this.api);

  Future<PagedResult<Task>> listPage({
    int limit = 20,
    int offset = 0,
    String? taskStatus,
    bool overdue = false,
    bool today = false,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (taskStatus != null && taskStatus.isNotEmpty) params['task_status'] = taskStatus;
    if (overdue) params['overdue'] = true;
    if (today) params['today'] = true;

    final res = await api.get('/tasks', params: params);
    return PagedResult.fromData(res['data'] as Map<String, dynamic>, Task.fromJson);
  }

  Future<List<Task>> list({
    int limit = 20,
    int offset = 0,
    String? taskStatus,
    bool overdue = false,
    bool today = false,
  }) async {
    final page = await listPage(limit: limit, offset: offset, taskStatus: taskStatus, overdue: overdue, today: today);
    return page.items;
  }

  Future<Task> get(String id) async {
    final res = await api.get('/tasks/$id');
    return Task.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Task> create(Map<String, dynamic> data) async {
    final res = await api.post('/tasks', data: data);
    return Task.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Task> update(String id, Map<String, dynamic> data) async {
    final res = await api.put('/tasks/$id', data: data);
    return Task.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Task> complete(String id) async {
    final res = await api.post('/tasks/$id/complete', data: const {});
    return Task.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await api.delete('/tasks/$id');
  }
}
