import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/powersync/powersync_crud_mapper.dart';
import 'package:client_flutter/data/powersync/sync_push_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSyncPushApiClient extends ApiClient {
  Map<String, dynamic>? postedData;

  FakeSyncPushApiClient() : super(baseUrl: 'http://example.invalid/api/v1');

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    expect(path, '/sync/encrypted');
    postedData = data;
    return {
      'success': true,
      'data': {
        'applied': 1,
        'skipped': 0,
        'results': [
          {
            'entity_type': 'memo',
            'entity_id': 'memo-1',
            'operation': 'upsert',
            'status': 'applied',
            'revision': 1,
          },
        ],
      },
    };
  }
}

void main() {
  test(
    'SyncPushService posts opaque envelopes to encrypted endpoint',
    () async {
      final api = FakeSyncPushApiClient();
      final service = SyncPushService(api);
      final request = EncryptedSyncPushRequestPayload(
        clientId: 'device-1',
        ignoredCount: 0,
        changes: [
          EncryptedEntityEnvelope(
            id: 'memo-1',
            userId: 'account-1',
            entityType: 'memo',
            revision: 1,
            lifecycleStatus: EncryptedEntityLifecycleStatus.active,
            updatedAt: DateTime.utc(2026, 8, 15, 10),
            keyVersion: 1,
            encryptionVersion: 1,
            nonce: 'bm9uY2U=',
            ciphertext: 'Y2lwaGVydGV4dA==',
          ),
        ],
      );

      final result = await service.push(request);

      expect(result.applied, 1);
      expect(result.skipped, 0);
      expect(result.results.single['status'], 'applied');
      expect(api.postedData, request.toJson());
      expect(api.postedData.toString(), isNot(contains('content_markdown')));
    },
  );

  test('SyncPushService rejects empty encrypted payloads', () async {
    final service = SyncPushService(FakeSyncPushApiClient());
    const request = EncryptedSyncPushRequestPayload(
      clientId: 'device-empty',
      ignoredCount: 1,
      changes: [],
    );

    expect(() => service.push(request), throwsArgumentError);
  });
}
