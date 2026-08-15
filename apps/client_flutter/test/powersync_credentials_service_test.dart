import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCredentialsApiClient extends ApiClient {
  FakeCredentialsApiClient() : super(baseUrl: 'http://example.invalid/api/v1');

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
        'user_id': 'local-dev',
        'expires_at': '2026-07-03T10:00:00Z',
        'mode': 'development',
      },
    };
  }
}

void main() {
  test('PowerSyncCredentialsService fetches credentials from API', () async {
    final service = PowerSyncCredentialsService(FakeCredentialsApiClient());

    final credentials = await service.fetchCredentials();

    expect(credentials.endpoint, 'http://localhost:8204');
    expect(credentials.tokenStatus, '已获取');
    expect(credentials.userId, 'local-dev');
    expect(credentials.mode, 'development');
    expect(credentials.expiresAt, DateTime.utc(2026, 7, 3, 10));
  });
}
