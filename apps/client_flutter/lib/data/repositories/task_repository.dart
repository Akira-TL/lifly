import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/domain/entities/task.dart';

class TaskRepository {
  final ApiClient api;

  TaskRepository(this.api);

  Future<List<Task>> list({
    int limit = 20,
    int offset = 0,
    String? taskStatus,
    bool overdue = false,
    bool today = false,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (taskStatus != null) params['task_status'] = taskStatus;
    if (overdue) params['overdue'] = true;
    if (today) params['today'] = true;

    final res = await api.get('/tasks', params: params);
    final items = res['data']['items'] as List;
    return items.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
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
