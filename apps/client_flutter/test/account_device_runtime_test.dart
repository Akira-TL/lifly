import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/pake_client_adapter.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
import 'package:client_flutter/data/device/device_repository.dart';
import 'package:client_flutter/features/settings/account_device_runtime.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySessionStore implements AuthSessionStore {
  AuthSession? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<AuthSession?> read() async => value;

  @override
  Future<String?> readAccessToken() async => value?.accessToken;

  @override
  Future<void> write(AuthSession session) async => value = session;
}

class _FakeIdentityStore implements DeviceIdentityStore {
  bool cleared = false;

  @override
  Future<void> clear() async => cleared = true;

  @override
  Future<DeviceIdentity> loadOrCreate() async => const DeviceIdentity(
    deviceId: 'web-1',
    publicKey: 'public-web-1',
    keyVersion: 1,
  );

  @override
  Future<SecretKey> deriveSharedSecret({
    required String remotePublicKey,
  }) async => SecretKey(List<int>.filled(32, 7));
}

class _RuntimeApiClient extends ApiClient {
  final requests = <String>[];

  _RuntimeApiClient(AuthSessionStore sessions)
    : super(
        baseUrl: 'http://example.invalid/api/v1',
        accessTokenProvider: sessions.readAccessToken,
      );

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    requests.add('POST $path');
    if (path == '/auth/revoke') return const {};
    throw StateError('Unexpected POST $path');
  }
}

class _DeviceTransport implements DeviceTransport {
  final bool failRevoke;
  final requests = <String>[];

  _DeviceTransport({this.failRevoke = false});

  @override
  Future<Map<String, dynamic>> get(String path) async {
    requests.add('GET $path');
    return {'devices': <Object>[]};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    requests.add('POST $path');
    if (path == '/devices/web-1/revoke') {
      if (failRevoke) throw StateError('device revoke failed');
      return {
        'device': _deviceJson(trustState: 'revoked'),
        'revoked_sessions': 1,
      };
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async => throw StateError('Unexpected PUT $path');
}

AuthSession _session() => AuthSession(
  account: const AccountProfile(
    accountId: 'account-1',
    phoneE164: '+8613800138011',
    displayName: 'Acceptance',
    accountStatus: 'active',
    plan: 'demo',
  ),
  device: DeviceDescriptor.fromJson(_deviceJson()),
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  accessExpiresAt: DateTime.utc(2026, 8, 16, 15),
  refreshExpiresAt: DateTime.utc(2026, 9, 16, 15),
);

Map<String, dynamic> _deviceJson({String trustState = 'trusted'}) => {
  'device_id': 'web-1',
  'account_id': 'account-1',
  'display_name': 'Lifly web',
  'platform': 'web',
  'public_key': 'public-web-1',
  'trust_state': trustState,
  'capability_report': {
    'protocol_version': 1,
    'capabilities': <String>[],
    'supported_tools': <String>[],
  },
  'is_default_compute_node': false,
  'key_version': 1,
  'protocol_version': 1,
};

DefaultAccountDeviceRuntime _runtime({
  required _MemorySessionStore sessions,
  required _FakeIdentityStore identity,
  required _DeviceTransport transport,
  _RuntimeApiClient? api,
}) => DefaultAccountDeviceRuntime(
  api ?? _RuntimeApiClient(sessions),
  pake: const UnavailableOpaqueClientAdapter(),
  sessions: sessions,
  deviceIdentity: identity,
  devices: DeviceRepository(transport),
);

void main() {
  test('logout is local-only and preserves Device identity', () async {
    final sessions = _MemorySessionStore()..value = _session();
    final identity = _FakeIdentityStore();
    final transport = _DeviceTransport();
    final runtime = _runtime(
      sessions: sessions,
      identity: identity,
      transport: transport,
    );

    final snapshot = await runtime.logout();

    expect(snapshot.session, isNull);
    expect(transport.requests, isEmpty);
    expect(await sessions.read(), isNull);
    expect(identity.cleared, isFalse);
  });

  test('remote session revoke is separate from Device revoke', () async {
    final sessions = _MemorySessionStore()..value = _session();
    final identity = _FakeIdentityStore();
    final transport = _DeviceTransport();
    final api = _RuntimeApiClient(sessions);
    final runtime = _runtime(
      sessions: sessions,
      identity: identity,
      transport: transport,
      api: api,
    );

    await runtime.revokeSession();

    expect(api.requests, ['POST /auth/revoke']);
    expect(transport.requests, isEmpty);
    expect(await sessions.read(), isNull);
    expect(identity.cleared, isFalse);
  });

  test(
    'revoking current device clears session but preserves local identity',
    () async {
      final sessions = _MemorySessionStore()..value = _session();
      final identity = _FakeIdentityStore();
      final transport = _DeviceTransport();
      final runtime = _runtime(
        sessions: sessions,
        identity: identity,
        transport: transport,
      );

      final snapshot = await runtime.revokeDevice('web-1');

      expect(snapshot.session, isNull);
      expect(transport.requests, ['POST /devices/web-1/revoke']);
      expect(await sessions.read(), isNull);
      expect(identity.cleared, isFalse);
    },
  );

  test(
    'failed Device revoke keeps session and local Device identity',
    () async {
      final sessions = _MemorySessionStore()..value = _session();
      final identity = _FakeIdentityStore();
      final transport = _DeviceTransport(failRevoke: true);
      final runtime = _runtime(
        sessions: sessions,
        identity: identity,
        transport: transport,
      );

      await expectLater(
        runtime.revokeDevice('web-1'),
        throwsA(isA<StateError>()),
      );

      expect(await sessions.read(), isNotNull);
      expect(identity.cleared, isFalse);
    },
  );

  test('Device identity destruction requires signed-out state', () async {
    final sessions = _MemorySessionStore()..value = _session();
    final identity = _FakeIdentityStore();
    final runtime = _runtime(
      sessions: sessions,
      identity: identity,
      transport: _DeviceTransport(),
    );

    await expectLater(
      runtime.destroyLocalDeviceIdentity(),
      throwsA(isA<StateError>()),
    );
    expect(identity.cleared, isFalse);

    await runtime.logout();
    await runtime.destroyLocalDeviceIdentity();
    expect(identity.cleared, isTrue);
  });
}
