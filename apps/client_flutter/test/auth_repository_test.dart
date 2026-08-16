import 'package:client_flutter/data/auth/auth_repository.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/pake_client_adapter.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
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

class _FakeDeviceIdentityStore implements DeviceIdentityStore {
  bool cleared = false;

  @override
  Future<void> clear() async => cleared = true;

  @override
  Future<DeviceIdentity> loadOrCreate() async => const DeviceIdentity(
    deviceId: 'device-1',
    publicKey: 'device-public-key',
    keyVersion: 1,
  );

  @override
  Future<SecretKey> deriveSharedSecret({
    required String remotePublicKey,
  }) async => SecretKey(List<int>.filled(32, 7));
}

class _FakePake implements PakeClientAdapter {
  @override
  String get protocol => 'opaque-rfc9807';

  @override
  int get protocolVersion => 1;

  @override
  Future<PakeClientStart> startRegistration({required String password}) async {
    expect(password, 'correct horse battery staple');
    return const PakeClientStart(
      clientRequest: 'registration-request',
      clientState: 'registration-state',
    );
  }

  @override
  Future<PakeClientFinish> finishRegistration({
    required String clientState,
    required String serverResponse,
  }) async {
    expect(clientState, 'registration-state');
    expect(serverResponse, 'registration-response');
    return const PakeClientFinish(
      clientMessage: 'registration-upload',
      exportKey: [1, 2, 3, 4],
    );
  }

  @override
  Future<PakeClientStart> startLogin({required String password}) async {
    return const PakeClientStart(
      clientRequest: 'login-request',
      clientState: 'login-state',
    );
  }

  @override
  Future<PakeClientFinish> finishLogin({
    required String clientState,
    required String serverResponse,
  }) async {
    return const PakeClientFinish(
      clientMessage: 'login-finish',
      exportKey: [5, 6, 7, 8],
    );
  }
}

class _Request {
  final String path;
  final Map<String, dynamic>? data;

  const _Request(this.path, this.data);
}

class _FakeTransport implements AuthTransport {
  final requests = <_Request>[];

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    requests.add(_Request(path, data));
    if (path == '/auth/register/start') {
      return {
        'protocol': 'opaque-rfc9807',
        'protocol_version': 1,
        'flow_id': 'flow-1',
        'phone_e164': '+8613800138000',
        'server_response': 'registration-response',
        'expires_at': '2026-08-15T12:00:00Z',
      };
    }
    if (path == '/auth/register/finish') {
      return _sessionJson(accessToken: 'access-1', refreshToken: 'refresh-1');
    }
    if (path == '/auth/refresh') {
      return _sessionJson(accessToken: 'access-2', refreshToken: 'refresh-2');
    }
    if (path == '/auth/revoke') return {'ok': true};
    throw StateError('Unexpected path: $path');
  }
}

Map<String, dynamic> _sessionJson({
  required String accessToken,
  required String refreshToken,
}) => {
  'account': {
    'schema_version': 1,
    'account_id': 'account-1',
    'phone_e164': '+8613800138000',
    'display_name': 'Demo',
    'account_status': 'active',
    'plan': 'demo',
  },
  'device': {
    'device_id': 'device-1',
    'account_id': 'account-1',
    'display_name': 'Phone',
    'platform': 'android',
    'public_key': 'device-public-key',
    'trust_state': 'trusted',
    'capability_report': {
      'protocol_version': 1,
      'capabilities': [],
      'supported_tools': [],
    },
    'is_default_compute_node': false,
    'key_version': 1,
    'protocol_version': 1,
  },
  'access_token': accessToken,
  'refresh_token': refreshToken,
  'token_type': 'bearer',
  'access_expires_at': '2026-08-16T12:00:00Z',
  'refresh_expires_at': '2026-09-15T12:00:00Z',
};

void main() {
  test(
    'registration sends OPAQUE messages but never password or export key',
    () async {
      final transport = _FakeTransport();
      final sessions = _MemorySessionStore();
      final repository = AuthRepository(
        transport,
        sessions,
        _FakeDeviceIdentityStore(),
        _FakePake(),
        const DeviceClientProfile(displayName: 'Phone', platform: 'android'),
      );

      final result = await repository.register(
        phone: '138 0013 8000',
        password: 'correct horse battery staple',
        displayName: 'Demo',
      );

      expect(result.exportKey, [1, 2, 3, 4]);
      expect(result.session.device.trustState, DeviceTrustState.trusted);
      expect(await sessions.readAccessToken(), 'access-1');
      final outbound = transport.requests
          .map((item) => item.data.toString())
          .join('\n');
      expect(outbound, isNot(contains('correct horse battery staple')));
      expect(outbound, isNot(contains('[1, 2, 3, 4]')));
      expect(
        transport.requests.last.data?['device'],
        containsPair('public_key', 'device-public-key'),
      );
    },
  );

  test(
    'refresh, remote revoke, local session clear and identity destroy are separate',
    () async {
      final transport = _FakeTransport();
      final sessions = _MemorySessionStore();
      sessions.value = AuthSession.fromJson(
        _sessionJson(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );
      final identity = _FakeDeviceIdentityStore();
      final repository = AuthRepository(
        transport,
        sessions,
        identity,
        _FakePake(),
        const DeviceClientProfile(displayName: 'Phone', platform: 'android'),
      );

      final refreshed = await repository.refresh();
      expect(refreshed?.accessToken, 'access-2');
      expect(sessions.value?.refreshToken, 'refresh-2');

      await repository.revokeRemoteSession();
      expect(await sessions.read(), isNotNull);
      expect(identity.cleared, isFalse);
      expect(transport.requests.last.path, '/auth/revoke');

      await repository.clearSession();
      expect(await sessions.read(), isNull);
      expect(identity.cleared, isFalse);

      await repository.destroyDeviceIdentity();
      expect(identity.cleared, isTrue);
    },
  );
}
