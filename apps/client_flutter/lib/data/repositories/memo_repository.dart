import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';
import 'package:client_flutter/domain/entities/memo.dart';
import 'package:client_flutter/features/asset/data/asset_e2ee_sync_adapter.dart';
import 'package:uuid/uuid.dart';

class MemoRepository {
  final ApiClient api;
  final LocalCoreBridge? localCore;
  final LiflyDataMode dataMode;
  final AssetE2eeCoordinator? assetE2ee;
  final String Function() _newAssetRefId;
  final DateTime Function() _now;

  MemoRepository(
    this.api, {
    this.localCore,
    this.dataMode = LiflyDataMode.api,
    this.assetE2ee,
    String Function()? newAssetRefId,
    DateTime Function()? now,
  }) : _newAssetRefId = newAssetRefId ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  bool get _useLocalCore =>
      dataMode == LiflyDataMode.local && localCore != null;

  bool get _hasLocalCore => localCore != null;

  Future<PagedResult<Memo>> listPage({
    int limit = 20,
    int offset = 0,
    String? type,
    String? q,
    String? tag,
    String? classificationStatus,
  }) async {
    if (_useLocalCore) {
      final records = await localCore!.searchMemos({
        'q': q,
        'limit': limit + offset,
      }, LocalCoreContext.flutterUser());
      var filtered = type == null || type.isEmpty
          ? records
          : records.where((memo) => memo.type == type).toList();
      if (tag != null && tag.isNotEmpty) {
        filtered = filtered.where((memo) => memo.tags.contains(tag)).toList();
      }
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
    if (tag != null && tag.isNotEmpty) params['tag'] = tag;
    if (classificationStatus != null && classificationStatus.isNotEmpty) {
      params['classification_status'] = classificationStatus;
    }

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
    String? tag,
    String? classificationStatus,
  }) async {
    final page = await listPage(
      limit: limit,
      offset: offset,
      type: type,
      q: q,
      tag: tag,
      classificationStatus: classificationStatus,
    );
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

  Future<List<Map<String, dynamic>>> classifications(String memoId) async {
    if (dataMode == LiflyDataMode.local) {
      final items = await localCore!.getMemoClassifications({
        'memo_id': memoId,
      }, LocalCoreContext.flutterUser());
      return items.map(_classificationToMap).toList(growable: false);
    }

    try {
      final res = await api.get('/memos/$memoId/classifications');
      final items = res['data'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
    } catch (error) {
      if (_hasLocalCore) {
        final items = await localCore!.getMemoClassifications({
          'memo_id': memoId,
        }, LocalCoreContext.flutterUser());
        return items.map(_classificationToMap).toList(growable: false);
      }
      throw StateError('Memo classifications unavailable: $error');
    }
  }

  Future<List<Map<String, dynamic>>> generateClassifications(
    String memoId, {
    bool replaceSuggested = true,
    bool includeUserTags = true,
  }) async {
    final data = {
      'replace_suggested': replaceSuggested,
      'include_user_tags': includeUserTags,
    };
    if (dataMode == LiflyDataMode.local) {
      final items = await localCore!.generateMemoClassifications({
        ...data,
        'memo_id': memoId,
      }, LocalCoreContext.flutterUser());
      return items.map(_classificationToMap).toList(growable: false);
    }

    final res = await api.post(
      '/memos/$memoId/classifications/generate',
      data: data,
    );
    final items = res['data'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> confirmClassification(
    String memoId,
    Map<String, dynamic> data,
  ) async {
    if (dataMode == LiflyDataMode.local) {
      final item = await localCore!.confirmMemoClassification({
        ...data,
        'memo_id': memoId,
      }, LocalCoreContext.flutterUser());
      return _classificationToMap(item);
    }

    final res = await api.post(
      '/memos/$memoId/classifications/confirm',
      data: data,
    );
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<Map<String, dynamic>> rejectClassification(
    String memoId,
    Map<String, dynamic> data,
  ) async {
    if (dataMode == LiflyDataMode.local) {
      final item = await localCore!.rejectMemoClassification({
        ...data,
        'memo_id': memoId,
      }, LocalCoreContext.flutterUser());
      return _classificationToMap(item);
    }

    final res = await api.post(
      '/memos/$memoId/classifications/reject',
      data: data,
    );
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> tagSummary({String kind = 'memo'}) async {
    if (dataMode == LiflyDataMode.local) {
      final items = await localCore!.getTagSummary({
        'kind': kind,
      }, LocalCoreContext.flutterUser());
      return items.map(_tagSummaryToMap).toList(growable: false);
    }

    try {
      final res = await api.get('/tags/summary', params: {'kind': kind});
      final items = res['data'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
    } catch (error) {
      if (_hasLocalCore) {
        final items = await localCore!.getTagSummary({
          'kind': kind,
        }, LocalCoreContext.flutterUser());
        return items.map(_tagSummaryToMap).toList(growable: false);
      }
      throw StateError('Tag summary unavailable: $error');
    }
  }

  Future<List<Map<String, dynamic>>> tagMetadata({String kind = 'memo'}) async {
    if (dataMode == LiflyDataMode.local) {
      final items = await localCore!.listTagMetadata({
        'kind': kind,
      }, LocalCoreContext.flutterUser());
      return items.map(_tagMetadataToMap).toList(growable: false);
    }

    final res = await api.get('/tags/metadata', params: {'kind': kind});
    final items = res['data'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> upsertTagMetadata(
    Map<String, dynamic> data,
  ) async {
    if (dataMode == LiflyDataMode.local) {
      final item = await localCore!.upsertTagMetadata(
        data,
        LocalCoreContext.flutterUser(),
      );
      return _tagMetadataToMap(item);
    }

    final res = await api.post('/tags/metadata', data: data);
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<Map<String, dynamic>> deleteTagMetadata(
    String name, {
    String kind = 'memo',
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final item = await localCore!.deleteTagMetadata({
        'name': name,
        'kind': kind,
      }, LocalCoreContext.flutterUser());
      return _tagMetadataToMap(item);
    }

    final res = await api.delete(
      '/tags/metadata/${Uri.encodeComponent(name)}?kind=${Uri.encodeQueryComponent(kind)}',
    );
    return Map<String, dynamic>.from(res['data'] as Map);
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

  Future<Memo> restore(String id) async {
    if (_useLocalCore) {
      final record = await localCore!.restoreMemo({
        'memo_id': id,
      }, LocalCoreContext.flutterUser());
      return _memoFromLocal(record);
    }

    await api.post('/trash/memo/$id/restore', data: const {});
    return get(id);
  }

  Future<List<MemoAssetRef>> listAssets(String memoId) async {
    final coordinator = assetE2ee;
    if (coordinator == null) {
      throw StateError(
        'Memo attachment E2EE runtime is not configured; plaintext relation fallback is disabled',
      );
    }
    return coordinator.listMemoAssetRefs(memoId);
  }

  Future<List<MemoAssetRef>> bindAsset(
    String memoId,
    String assetId, {
    String refType = 'attachment',
  }) async {
    final coordinator = assetE2ee;
    if (coordinator == null) {
      throw StateError(
        'Memo attachment E2EE runtime is not configured; plaintext relation fallback is disabled',
      );
    }
    await coordinator.syncMemoAssetRef(
      refId: _newAssetRefId(),
      memoId: memoId,
      assetId: assetId,
      refType: refType,
      now: _now().toUtc(),
    );
    return coordinator.listMemoAssetRefs(memoId);
  }

  Future<void> unbindAsset(String memoId, String assetId) async {
    final coordinator = assetE2ee;
    if (coordinator == null) {
      throw StateError(
        'Memo attachment E2EE runtime is not configured; plaintext relation fallback is disabled',
      );
    }
    await coordinator.removeMemoAssetRef(
      memoId: memoId,
      assetId: assetId,
      now: _now().toUtc(),
    );
  }

  Map<String, dynamic> _classificationToMap(LocalMemoClassification item) {
    return {
      'id': item.id,
      'memo_id': item.memoId,
      'tag': item.tag,
      'source': item.source,
      'status': item.status,
      'confidence': item.confidence,
      'reason': item.reason,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
      'confirmed_at': item.confirmedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _tagSummaryToMap(LocalTagSummary item) {
    return {
      'tag': item.tag,
      'kind': item.kind,
      'count': item.count,
      'confirmed_count': item.confirmedCount,
      'suggested_count': item.suggestedCount,
      'color_token': item.colorToken,
      'icon_token': item.iconToken,
      'sort_order': item.sortOrder,
    };
  }

  Map<String, dynamic> _tagMetadataToMap(LocalTagMetadata item) {
    return {
      'id': item.id,
      'name': item.name,
      'kind': item.kind,
      'color_token': item.colorToken,
      'icon_token': item.iconToken,
      'sort_order': item.sortOrder,
      'status': item.status,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
    };
  }

  Memo _memoFromLocal(LocalMemoRecord record) {
    return Memo(
      id: record.id,
      type: record.type,
      title: record.title,
      contentMarkdown: record.contentMarkdown,
      tags: record.tags,
      mood: record.mood,
      status: record.status,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }
}
