import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/domain/entities/asset.dart';

class AssetRepository {
  final ApiClient api;

  AssetRepository(this.api);

  Future<List<Asset>> list({
    int limit = 20,
    int offset = 0,
    String? kind,
    String? assetType,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (kind != null) params['kind'] = kind;
    if (assetType != null) params['asset_type'] = assetType;

    final res = await api.get('/assets', params: params);
    final items = res['data']['items'] as List;
    return items.map((e) => Asset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Asset> get(String id) async {
    final res = await api.get('/assets/$id');
    return Asset.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> createUploadUrl({
    required String filename,
    String? mimeType,
    int? sizeBytes,
    String assetType = 'file',
  }) async {
    final res = await api.post('/assets/create-upload-url', data: {
      'filename': filename,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'asset_type': assetType,
    });
    return res['data'] as Map<String, dynamic>;
  }

  Future<Asset> registerExternalUrl({
    required String externalUrl,
    String? externalProvider,
    String assetType = 'link',
    String? title,
    String? previewUrl,
  }) async {
    final res = await api.post('/assets/register-external-url', data: {
      'external_url': externalUrl,
      'external_provider': externalProvider,
      'asset_type': assetType,
      'title': title,
      'preview_url': previewUrl,
    });
    final data = res['data'] as Map<String, dynamic>;
    return Asset.fromJson((data['asset'] ?? data) as Map<String, dynamic>);
  }

  Future<Asset> uploadComplete(String assetId, {String? sha256, int? sizeBytes}) async {
    final res = await api.post('/assets/$assetId/upload-complete', data: {
      'sha256': sha256,
      'size_bytes': sizeBytes,
    }..removeWhere((_, v) => v == null));
    return Asset.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getDownloadUrl(String assetId) async {
    final res = await api.get('/assets/$assetId/download-url');
    return res['data'] as Map<String, dynamic>;
  }

  Future<Asset> update(String id, Map<String, dynamic> data) async {
    final res = await api.put('/assets/$id', data: data);
    return Asset.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await api.delete('/assets/$id');
  }
}
