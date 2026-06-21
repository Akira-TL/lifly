import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/domain/entities/memo.dart';

class MemoRepository {
  final ApiClient api;

  MemoRepository(this.api);

  Future<List<Memo>> list({int limit = 20, int offset = 0, String? type, String? q}) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (type != null) params['type'] = type;
    if (q != null) params['q'] = q;

    final res = await api.get('/memos', params: params);
    final items = res['data']['items'] as List;
    return items.map((e) => Memo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Memo> get(String id) async {
    final res = await api.get('/memos/$id');
    return Memo.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Memo> create(Map<String, dynamic> data) async {
    final res = await api.post('/memos', data: data);
    return Memo.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Memo> update(String id, Map<String, dynamic> data) async {
    final res = await api.put('/memos/$id', data: data);
    return Memo.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await api.delete('/memos/$id');
  }
}
