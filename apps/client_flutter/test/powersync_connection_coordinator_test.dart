import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/powersync/powersync_connection_coordinator.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConnectionApiClient extends ApiClient {
  FakeConnectionApiClient() : super(baseUrl: 'http://example.invalid/api/v1');

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    expect(path, '/sync/credentials');
    return {
      'success': true,
      'data': {
        'endpoint': 'http://localhost:8204',
        'token': 'token-value',
        'user_id': 'account-1',
        'device_id': 'device-1',
        'expires_at': '2026-07-03T10:00:00Z',
        'mode': 'authenticated',
      },
    };
  }
}

class FakeConnectSyncService extends SyncService {
  bool initialized = false;
  bool connected = false;
  bool disconnected = false;

  FakeConnectSyncService()
    : super(api: ApiClient(baseUrl: 'http://example.invalid/api/v1'));

  @override
  Future<void> ensureInitialized() async {
    initialized = true;
  }

  @override
  Future<void> connectWithCredentials(credentials) async {
    connected = true;
  }

  @override
  Future<void> disconnect({bool clearLocal = false}) async {
    disconnected = true;
  }
}

class FailingConnectSyncService extends FakeConnectSyncService {
  @override
  Future<void> connectWithCredentials(credentials) async {
    throw StateError('connect failed');
  }
}

void main() {
  test(
    'PowerSyncConnectionCoordinator connects with fetched credentials',
    () async {
      final syncService = FakeConnectSyncService();
      final coordinator = PowerSyncConnectionCoordinator(
        credentialsService: PowerSyncCredentialsService(
          FakeConnectionApiClient(),
        ),
        syncService: syncService,
      );

      final diagnostics = await coordinator.connect();

      expect(syncService.initialized, isTrue);
      expect(syncService.connected, isTrue);
      expect(diagnostics.status, 'connected');
      expect(diagnostics.statusLabel, '已连接');
      expect(diagnostics.credentials?.userId, 'account-1');
      expect(diagnostics.credentials?.deviceId, 'device-1');
      expect(diagnostics.connectedAt, isNotNull);
    },
  );

  test(
    'PowerSyncConnectionCoordinator disconnects current sync service',
    () async {
      final syncService = FakeConnectSyncService();
      final coordinator = PowerSyncConnectionCoordinator(
        credentialsService: PowerSyncCredentialsService(
          FakeConnectionApiClient(),
        ),
        syncService: syncService,
      );

      await coordinator.connect();
      final diagnostics = await coordinator.disconnect();

      expect(syncService.disconnected, isTrue);
      expect(diagnostics.status, 'disconnected');
      expect(diagnostics.statusLabel, '已断开');
      expect(diagnostics.disconnectedAt, isNotNull);
    },
  );

  test('PowerSyncConnectionCoordinator reports connect failure', () async {
    final coordinator = PowerSyncConnectionCoordinator(
      credentialsService: PowerSyncCredentialsService(
        FakeConnectionApiClient(),
      ),
      syncService: FailingConnectSyncService(),
    );

    final diagnostics = await coordinator.connect();

    expect(diagnostics.status, 'failed');
    expect(diagnostics.statusLabel, '失败');
    expect(diagnostics.error, contains('connect failed'));
  });
}
