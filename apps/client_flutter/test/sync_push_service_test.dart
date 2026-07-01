import 'package:client_flutter/data/api/api_client.dart';
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
    expect(path, '/sync/push');
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
  test('SyncPushService posts mapped payload to sync push endpoint', () async {
    final api = FakeSyncPushApiClient();
    final service = SyncPushService(api);
    final request = SyncPushRequestPayload(
      clientId: 'lifly-flutter-1-1',
      ignoredCount: 0,
      changes: [
        SyncPushChangePayload(
          entityType: 'memo',
          operation: 'upsert',
          entityId: 'memo-1',
          userId: 'local-dev',
          revision: 1,
          createdAt: DateTime.utc(2026, 7, 2, 9),
          updatedAt: DateTime.utc(2026, 7, 2, 9),
          deletedAt: null,
          source: 'flutter',
          data: const {
            'type': 'memo',
            'content_markdown': 'body',
            'status': 'active',
          },
        ),
      ],
    );

    final result = await service.push(request);

    expect(result.applied, 1);
    expect(result.skipped, 0);
    expect(result.results.single['status'], 'applied');
    expect(api.postedData, request.toJson());
  });

  test('SyncPushService rejects empty push payloads', () async {
    final service = SyncPushService(FakeSyncPushApiClient());
    final request = SyncPushRequestPayload(
      clientId: 'lifly-flutter-empty',
      ignoredCount: 1,
      changes: const [],
    );

    expect(() => service.push(request), throwsArgumentError);
  });
}
