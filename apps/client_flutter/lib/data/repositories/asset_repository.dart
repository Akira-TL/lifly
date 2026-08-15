import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/domain/entities/asset.dart';
import 'package:client_flutter/features/asset/data/asset_e2ee_sync_adapter.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class AssetRepository {
  final ApiClient api;
  final Dio _storageClient;
  final AssetE2eeCoordinator? e2ee;
  final DateTime Function() _now;
  final Uuid _uuid;

  AssetRepository(
    this.api, {
    Dio? storageClient,
    this.e2ee,
    DateTime Function()? now,
    Uuid? uuid,
  }) : _storageClient = storageClient ?? Dio(),
       _now = now ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  Future<List<Asset>> list({
    int limit = 20,
    int offset = 0,
    String? kind,
    String? assetType,
  }) async {
    final coordinator = e2ee;
    if (coordinator != null) {
      return coordinator.listLocal(
        limit: limit,
        offset: offset,
        kind: kind,
        assetType: assetType,
      );
    }
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (kind != null) params['kind'] = kind;
    if (assetType != null) params['asset_type'] = assetType;
    final res = await api.get('/assets', params: params);
    final items = res['data']['items'] as List;
    return items
        .map((item) => Asset.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Asset> get(String id) async {
    final coordinator = e2ee;
    if (coordinator != null) {
      final local = await coordinator.getLocal(id);
      if (local != null) return local;
    }
    final res = await api.get('/assets/$id');
    return Asset.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> createUploadUrl() async {
    final res = await api.post(
      '/assets/e2ee/create-upload-url',
      data: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<Asset> uploadBytes({
    required String filename,
    required List<int> bytes,
    String? mimeType,
    String assetType = 'file',
  }) async {
    if (bytes.isEmpty) throw ArgumentError('Upload file must not be empty');
    final coordinator = _requireE2ee();
    final intent = await createUploadUrl();
    final assetId = intent['asset_id'] as String?;
    final uploadUrl = intent['upload_url'] as String?;
    final storageKey = intent['storage_key'] as String?;
    if (assetId == null ||
        assetId.isEmpty ||
        uploadUrl == null ||
        uploadUrl.isEmpty ||
        storageKey == null ||
        storageKey.isEmpty) {
      throw StateError('Encrypted asset upload intent is incomplete');
    }

    final prepared = await coordinator.encryptUpload(
      assetId: assetId,
      plaintext: bytes,
    );
    await _storageClient.put<void>(
      uploadUrl,
      data: prepared.encrypted.ciphertext,
      options: Options(
        headers: const {'content-type': 'application/octet-stream'},
        contentType: 'application/octet-stream',
        responseType: ResponseType.plain,
      ),
    );
    await api.post(
      '/assets/e2ee/$assetId/upload-complete',
      data: {
        'ciphertext_sha256': prepared.encrypted.ciphertextSha256,
        'ciphertext_size_bytes': prepared.encrypted.ciphertextSizeBytes,
      },
    );
    return coordinator.commitInternalAsset(
      assetId: assetId,
      filename: filename,
      assetType: assetType,
      mimeType: mimeType,
      storageKey: storageKey,
      prepared: prepared,
      now: _now().toUtc(),
    );
  }

  Future<Asset> registerExternalUrl({
    required String externalUrl,
    String? externalProvider,
    String assetType = 'link',
    String? title,
    String? previewUrl,
  }) async {
    final coordinator = _requireE2ee();
    return coordinator.registerExternalAsset(
      assetId: _uuid.v4(),
      externalUrl: externalUrl,
      externalProvider: externalProvider,
      assetType: assetType,
      title: title,
      now: _now().toUtc(),
    );
  }

  Future<Map<String, dynamic>> getDownloadUrl(String assetId) async {
    final res = await api.get('/assets/$assetId/download-url');
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<List<int>> downloadDecryptedBytes(String assetId) async {
    final coordinator = _requireE2ee();
    final intent = await getDownloadUrl(assetId);
    final url = intent['url'] as String?;
    if (url == null || url.isEmpty || intent['encrypted'] != true) {
      throw StateError('Encrypted asset download intent is incomplete');
    }
    final response = await _storageClient.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final ciphertext = response.data ?? const <int>[];
    return coordinator.decryptDownloadedAsset(
      assetId: assetId,
      ciphertext: ciphertext,
    );
  }

  Future<Asset> update(String id, Map<String, dynamic> data) async {
    throw StateError(
      'Asset metadata updates require the E2EE metadata editor; plaintext API updates are disabled',
    );
  }

  Future<void> delete(String id) async {
    final coordinator = _requireE2ee();
    final local = await coordinator.getLocal(id);
    await coordinator.trashAsset(id, now: _now().toUtc());
    if (local?.isInternal ?? false) {
      await api.delete('/assets/$id');
    }
  }

  Future<void> purge(String id) async {
    final coordinator = _requireE2ee();
    final local = await coordinator.getLocal(id);
    if (local?.isInternal ?? false) {
      await api.delete('/assets/e2ee/$id/purge');
    }
  }

  AssetE2eeCoordinator _requireE2ee() {
    final coordinator = e2ee;
    if (coordinator == null) {
      throw StateError(
        'Asset E2EE runtime is not configured; plaintext attachment fallback is disabled',
      );
    }
    return coordinator;
  }
}
