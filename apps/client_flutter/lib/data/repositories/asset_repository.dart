import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/domain/entities/asset.dart';
import 'package:dio/dio.dart';

class AssetRepository {
  final ApiClient api;
  final Dio _storageClient;

  AssetRepository(this.api, {Dio? storageClient})
    : _storageClient = storageClient ?? Dio();

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

  Future<Asset> uploadBytes({
    required String filename,
    required List<int> bytes,
    String? mimeType,
    String assetType = 'file',
  }) async {
    if (bytes.isEmpty) throw ArgumentError('Upload file must not be empty');
    final intent = await createUploadUrl(
      filename: filename,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      assetType: assetType,
    );
    final assetId = intent['asset_id'] as String?;
    final uploadUrl = intent['upload_url'] as String?;
    if (assetId == null || assetId.isEmpty || uploadUrl == null || uploadUrl.isEmpty) {
      throw StateError('Asset upload intent is incomplete');
    }
    final uploadIntent = intent['upload_intent'] as Map?;
    final rawHeaders = uploadIntent?['headers'] as Map?;
    final headers = <String, dynamic>{
      for (final entry in rawHeaders?.entries ?? const <MapEntry<dynamic, dynamic>>[])
        entry.key.toString(): entry.value,
    };
    if (mimeType != null && mimeType.isNotEmpty) {
      headers.putIfAbsent('content-type', () => mimeType);
    }
    await _storageClient.put<void>(
      uploadUrl,
      data: bytes,
      options: Options(
        headers: headers,
        contentType: mimeType ?? 'application/octet-stream',
        responseType: ResponseType.plain,
      ),
    );
    return uploadComplete(assetId, sizeBytes: bytes.length);
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
