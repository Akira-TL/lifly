import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';
import 'package:client_flutter/domain/entities/memo.dart';

class MemoRepository {
  final ApiClient api;

  MemoRepository(this.api);

  Future<PagedResult<Memo>> listPage({int limit = 20, int offset = 0, String? type, String? q}) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (q != null && q.isNotEmpty) params['q'] = q;

    final res = await api.get('/memos', params: params);
    return PagedResult.fromData(res['data'] as Map<String, dynamic>, Memo.fromJson);
  }

  Future<List<Memo>> list({int limit = 20, int offset = 0, String? type, String? q}) async {
    final page = await listPage(limit: limit, offset: offset, type: type, q: q);
    return page.items;
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
