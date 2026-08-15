import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/repositories/asset_repository.dart';
import 'package:client_flutter/domain/entities/asset.dart';
import 'package:client_flutter/features/asset/data/asset_e2ee_cipher.dart';
import 'package:client_flutter/features/asset/data/asset_e2ee_sync_adapter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'uploadBytes sends only encrypted object bytes and encrypted completion metadata',
    () async {
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
      final coordinator = _FakeAssetE2eeCoordinator();
      final repository = AssetRepository(
        api,
        storageClient: storage,
        e2ee: coordinator,
        now: () => DateTime.utc(2026, 8, 15, 10),
      );
      const plaintext = [108, 105, 102, 108, 121];

      final asset = await repository.uploadBytes(
        filename: 'notes.txt',
        bytes: plaintext,
        mimeType: 'text/plain',
        assetType: 'file',
      );

      expect(api.reservePayload, isEmpty);
      expect(uploadedRequest?.uri.toString(), 'https://storage.invalid/upload');
      final uploadedBytes = List<int>.from(uploadedRequest?.data as List);
      expect(AssetE2eeCipher.hasEncryptedAssetMagic(uploadedBytes), isTrue);
      expect(uploadedBytes, isNot(plaintext));
      expect(
        uploadedRequest?.headers['content-type'],
        'application/octet-stream',
      );
      expect(api.completedAssetId, 'asset-1');
      expect(api.completedCiphertextSize, uploadedBytes.length);
      expect(api.completedCiphertextSha256, hasLength(64));
      expect(coordinator.committedFilename, 'notes.txt');
      expect(coordinator.committedMimeType, 'text/plain');
      expect(asset.id, 'asset-1');
      expect(asset.displayName, 'notes.txt');
    },
  );

  test(
    'uploadBytes fails closed when ADK/sync coordinator is absent',
    () async {
      final repository = AssetRepository(_FakeAssetApiClient());

      expect(
        () => repository.uploadBytes(
          filename: 'secret.txt',
          bytes: const [1, 2, 3],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('plaintext attachment fallback is disabled'),
          ),
        ),
      );
    },
  );

  test(
    'external URL stays in encrypted coordinator and never reaches cloud API',
    () async {
      final api = _FakeAssetApiClient();
      final coordinator = _FakeAssetE2eeCoordinator();
      final repository = AssetRepository(api, e2ee: coordinator);

      final asset = await repository.registerExternalUrl(
        externalUrl: 'https://example.com/private-document',
        externalProvider: 'web',
        title: 'Private title',
      );

      expect(api.postedPaths, isEmpty);
      expect(coordinator.externalUrl, 'https://example.com/private-document');
      expect(coordinator.externalTitle, 'Private title');
      expect(asset.isExternal, isTrue);
    },
  );
}

class _FakeAssetApiClient extends ApiClient {
  _FakeAssetApiClient() : super(baseUrl: 'http://example.invalid/api/v1');

  Map<String, dynamic>? reservePayload;
  String? completedAssetId;
  String? completedCiphertextSha256;
  int? completedCiphertextSize;
  final List<String> postedPaths = [];

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    postedPaths.add(path);
    if (path == '/assets/e2ee/create-upload-url') {
      reservePayload = Map<String, dynamic>.from(data ?? const {});
      return {
        'data': {
          'asset_id': 'asset-1',
          'upload_url': 'https://storage.invalid/upload',
          'storage_key': 'attachments/account-1/asset-1/payload.e2ee',
        },
      };
    }
    if (path == '/assets/e2ee/asset-1/upload-complete') {
      completedAssetId = 'asset-1';
      completedCiphertextSha256 = data?['ciphertext_sha256'] as String?;
      completedCiphertextSize = data?['ciphertext_size_bytes'] as int?;
      return const {
        'data': {
          'id': 'asset-1',
          'user_id': 'account-1',
          'kind': 'internal',
          'asset_type': 'file',
          'title': null,
          'filename': null,
          'mime_type': 'application/octet-stream',
          'size_bytes': 100,
          'sha256': 'ciphertext-hash',
          'storage_provider': 'minio',
          'storage_key': 'attachments/account-1/asset-1/payload.e2ee',
          'external_url': null,
          'external_provider': null,
          'visibility': 'private',
          'sync_status': 'synced',
          'status': 'active',
          'created_at': '2026-08-15T10:00:00Z',
          'updated_at': '2026-08-15T10:00:01Z',
        },
      };
    }
    throw StateError('Unexpected path: $path');
  }
}

class _FakeAssetE2eeCoordinator implements AssetE2eeCoordinator {
  final _cipher = AssetE2eeCipher(chunkSize: 16);
  final _adk = AccountDataKey.fromBytes(
    keyVersion: 1,
    bytes: List<int>.generate(32, (index) => index + 1),
  );

  String? committedFilename;
  String? committedMimeType;
  String? externalUrl;
  String? externalTitle;

  @override
  String get accountId => 'account-1';

  @override
  Future<PreparedAssetUpload> encryptUpload({
    required String assetId,
    required List<int> plaintext,
  }) async {
    return PreparedAssetUpload(
      await _cipher.encrypt(assetId: assetId, plaintext: plaintext, adk: _adk),
    );
  }

  @override
  Future<Asset> commitInternalAsset({
    required String assetId,
    required String filename,
    required String assetType,
    required String? mimeType,
    required String storageKey,
    required PreparedAssetUpload prepared,
    required DateTime now,
  }) async {
    committedFilename = filename;
    committedMimeType = mimeType;
    return Asset(
      id: assetId,
      userId: accountId,
      kind: 'internal',
      assetType: assetType,
      title: filename,
      filename: filename,
      mimeType: mimeType,
      sizeBytes: prepared.encrypted.plaintextSizeBytes,
      sha256: prepared.encrypted.plaintextSha256,
      storageProvider: 'minio',
      storageKey: storageKey,
      syncStatus: 'synced',
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<Asset> registerExternalAsset({
    required String assetId,
    required String externalUrl,
    required String? externalProvider,
    required String assetType,
    required String? title,
    required DateTime now,
  }) async {
    this.externalUrl = externalUrl;
    externalTitle = title;
    return Asset(
      id: assetId,
      userId: accountId,
      kind: 'external',
      assetType: assetType,
      title: title,
      filename: title,
      externalUrl: externalUrl,
      externalProvider: externalProvider,
      syncStatus: 'synced',
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<bool> applyRemoteEnvelope(EncryptedEntityEnvelope envelope) async =>
      false;

  @override
  Future<List<int>> decryptDownloadedAsset({
    required String assetId,
    required List<int> ciphertext,
  }) async => throw UnimplementedError();

  @override
  Future<Asset?> getLocal(String assetId) async => null;

  @override
  Future<List<Asset>> listLocal({
    int limit = 20,
    int offset = 0,
    String? kind,
    String? assetType,
  }) async => const [];

  @override
  Future<AssetKeyRotationResult> rotateAccountDataKey(
    AccountDataKey nextKey, {
    required DateTime now,
  }) async {
    return AssetKeyRotationResult(
      encryptedEntitiesRotated: 0,
      encryptedEntitiesSkipped: 0,
      assetKeysRewrapped: 0,
      keyVersion: nextKey.keyVersion,
    );
  }

  @override
  Future<void> syncMemoAssetRef({
    required String refId,
    required String memoId,
    required String assetId,
    String refType = 'attachment',
    String? positionHint,
    required DateTime now,
  }) async {}

  @override
  Future<void> tombstoneMemoAssetRef({
    required String refId,
    required int revision,
    required DateTime now,
  }) async {}

  @override
  Future<void> trashAsset(String assetId, {required DateTime now}) async {}
}
