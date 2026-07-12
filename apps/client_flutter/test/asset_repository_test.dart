import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/asset_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uploadBytes completes upload intent with selected file metadata', () async {
    final api = _FakeAssetApiClient();
    final storage = Dio();
    RequestOptions? uploadedRequest;
    storage.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          uploadedRequest = options;
          handler.resolve(
            Response<void>(requestOptions: options, statusCode: 200),
          );
        },
      ),
    );
    final repository = AssetRepository(api, storageClient: storage);

    final asset = await repository.uploadBytes(
      filename: 'notes.txt',
      bytes: const [108, 105, 102, 108, 121],
      mimeType: 'text/plain',
      assetType: 'file',
    );

    expect(api.createPayload, {
      'filename': 'notes.txt',
      'mime_type': 'text/plain',
      'size_bytes': 5,
      'asset_type': 'file',
    });
    expect(uploadedRequest?.uri.toString(), 'https://storage.invalid/upload');
    expect(uploadedRequest?.data, const [108, 105, 102, 108, 121]);
    expect(uploadedRequest?.headers['content-type'], 'text/plain');
    expect(api.completedAssetId, 'asset-1');
    expect(api.completedSize, 5);
    expect(asset.id, 'asset-1');
    expect(asset.syncStatus, 'synced');
  });
}

class _FakeAssetApiClient extends ApiClient {
  _FakeAssetApiClient() : super(baseUrl: 'http://example.invalid/api/v1');

  Map<String, dynamic>? createPayload;
  String? completedAssetId;
  int? completedSize;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    if (path == '/assets/create-upload-url') {
      createPayload = Map<String, dynamic>.from(data ?? const {});
      return {
        'data': {
          'asset_id': 'asset-1',
          'upload_url': 'https://storage.invalid/upload',
          'upload_intent': {
            'headers': {'content-type': 'text/plain'},
          },
        },
      };
    }
    if (path == '/assets/asset-1/upload-complete') {
      completedAssetId = 'asset-1';
      completedSize = data?['size_bytes'] as int?;
      return {
        'data': {
          'id': 'asset-1',
          'user_id': 'local-dev',
          'kind': 'internal',
          'asset_type': 'file',
          'title': 'notes.txt',
          'filename': 'notes.txt',
          'mime_type': 'text/plain',
          'size_bytes': 5,
          'sha256': null,
          'storage_provider': 'minio',
          'storage_key': 'attachments/local-dev/asset-1/notes.txt',
          'external_url': null,
          'external_provider': null,
          'visibility': 'private',
          'sync_status': 'synced',
          'status': 'active',
          'created_at': '2026-07-12T00:00:00Z',
          'updated_at': '2026-07-12T00:00:01Z',
        },
      };
    }
    throw StateError('Unexpected path: $path');
  }
}
