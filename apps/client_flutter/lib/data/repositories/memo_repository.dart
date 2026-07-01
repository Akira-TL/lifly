import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';
import 'package:client_flutter/domain/entities/memo.dart';

class MemoRepository {
  final ApiClient api;
  final LocalCoreBridge? localCore;
  final LiflyDataMode dataMode;

  MemoRepository(this.api, {this.localCore, this.dataMode = LiflyDataMode.api});

  bool get _useLocalCore =>
      dataMode == LiflyDataMode.local && localCore != null;

  Future<PagedResult<Memo>> listPage({
    int limit = 20,
    int offset = 0,
    String? type,
    String? q,
  }) async {
    if (_useLocalCore) {
      final records = await localCore!.searchMemos({
        'q': q,
        'limit': limit + offset,
      }, LocalCoreContext.flutterUser());
      final filtered = type == null || type.isEmpty
          ? records
          : records.where((memo) => memo.type == type).toList();
      final pageItems = filtered
          .skip(offset)
          .take(limit)
          .map(_memoFromLocal)
          .toList(growable: false);
      return PagedResult(
        items: pageItems,
        total: filtered.length,
        limit: limit,
        offset: offset,
      );
    }

    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (q != null && q.isNotEmpty) params['q'] = q;

    final res = await api.get('/memos', params: params);
    return PagedResult.fromData(
      res['data'] as Map<String, dynamic>,
      Memo.fromJson,
    );
  }

  Future<List<Memo>> list({
    int limit = 20,
    int offset = 0,
    String? type,
    String? q,
  }) async {
    final page = await listPage(limit: limit, offset: offset, type: type, q: q);
    return page.items;
  }

  Future<Memo> get(String id) async {
    if (_useLocalCore) {
      final records = await localCore!.searchMemos({
        'limit': 100,
      }, LocalCoreContext.flutterUser());
      for (final record in records) {
        if (record.id == id) return _memoFromLocal(record);
      }
      throw StateError('Memo not found: $id');
    }

    final res = await api.get('/memos/$id');
    return Memo.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Memo> create(Map<String, dynamic> data) async {
    if (_useLocalCore) {
      final record = await localCore!.createMemo(
        data,
        LocalCoreContext.flutterUser(),
      );
      return _memoFromLocal(record);
    }

    final res = await api.post('/memos', data: data);
    return Memo.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Memo> update(String id, Map<String, dynamic> data) async {
    if (_useLocalCore) {
      final record = await localCore!.updateMemo({
        ...data,
        'memo_id': id,
      }, LocalCoreContext.flutterUser());
      return _memoFromLocal(record);
    }

    final res = await api.put('/memos/$id', data: data);
    return Memo.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    if (_useLocalCore) {
      await localCore!.deleteMemo({
        'memo_id': id,
      }, LocalCoreContext.flutterUser());
      return;
    }

    await api.delete('/memos/$id');
  }

  Memo _memoFromLocal(LocalMemoRecord record) {
    return Memo(
      id: record.id,
      type: record.type,
      title: record.title,
      contentMarkdown: record.contentMarkdown,
      tags: record.tags,
      mood: null,
      status: record.status,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }
}
