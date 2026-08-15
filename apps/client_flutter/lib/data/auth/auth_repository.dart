import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/pake_client_adapter.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';

abstract interface class AuthTransport {
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data});
}

class ApiClientAuthTransport implements AuthTransport {
  final ApiClient _api;

  ApiClientAuthTransport(ApiClient api, AuthSessionStore sessions)
    : _api = api {
    _api.setAccessTokenProvider(sessions.readAccessToken);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) => _api.post(path, data: data);
}

class DeviceClientProfile {
  final String displayName;
  final String platform;
  final DeviceCapabilityReport capabilityReport;
  final bool makeDefaultComputeNode;

  const DeviceClientProfile({
    required this.displayName,
    required this.platform,
    this.capabilityReport = const DeviceCapabilityReport(),
    this.makeDefaultComputeNode = false,
  });

  DeviceEnrollment enrollment(DeviceIdentity identity) => DeviceEnrollment(
    deviceId: identity.deviceId,
    displayName: displayName,
    platform: platform,
    publicKey: identity.publicKey,
    capabilityReport: capabilityReport,
    makeDefaultComputeNode: makeDefaultComputeNode,
  );
}

class AuthCompletion {
  final AuthSession session;
  final List<int> exportKey;

  AuthCompletion({required this.session, required List<int> exportKey})
    : exportKey = List<int>.unmodifiable(exportKey);
}

class AuthRepository {
  final AuthTransport _transport;
  final AuthSessionStore _sessions;
  final DeviceIdentityStore _deviceIdentity;
  final PakeClientAdapter _pake;
  final DeviceClientProfile _deviceProfile;

  const AuthRepository(
    this._transport,
    this._sessions,
    this._deviceIdentity,
    this._pake,
    this._deviceProfile,
  );

  Future<AuthCompletion> register({
    required String phone,
    required String password,
    String? displayName,
    String region = 'CN',
  }) async {
    final pakeStart = await _pake.startRegistration(password: password);
    final start = _AuthStart.fromJson(
      await _transport.post(
        '/auth/register/start',
        data: {
          'phone': phone,
          'region': region,
          if (displayName != null && displayName.isNotEmpty)
            'display_name': displayName,
          'client_request': pakeStart.clientRequest,
        },
      ),
    );
    _validateProtocol(start);
    final pakeFinish = await _pake.finishRegistration(
      clientState: pakeStart.clientState,
      serverResponse: start.serverResponse,
    );
    final identity = await _deviceIdentity.loadOrCreate();
    final session = AuthSession.fromJson(
      await _transport.post(
        '/auth/register/finish',
        data: {
          'flow_id': start.flowId,
          'client_upload': pakeFinish.clientMessage,
          'device': _deviceProfile.enrollment(identity).toJson(),
        },
      ),
    );
    _validateSessionDevice(session, identity);
    await _sessions.write(session);
    return AuthCompletion(session: session, exportKey: pakeFinish.exportKey);
  }

  Future<AuthCompletion> login({
    required String phone,
    required String password,
    String region = 'CN',
  }) async {
    final pakeStart = await _pake.startLogin(password: password);
    final start = _AuthStart.fromJson(
      await _transport.post(
        '/auth/login/start',
        data: {
          'phone': phone,
          'region': region,
          'client_request': pakeStart.clientRequest,
        },
      ),
    );
    _validateProtocol(start);
    final pakeFinish = await _pake.finishLogin(
      clientState: pakeStart.clientState,
      serverResponse: start.serverResponse,
    );
    final identity = await _deviceIdentity.loadOrCreate();
    final session = AuthSession.fromJson(
      await _transport.post(
        '/auth/login/finish',
        data: {
          'flow_id': start.flowId,
          'client_finish': pakeFinish.clientMessage,
          'device': _deviceProfile.enrollment(identity).toJson(),
        },
      ),
    );
    _validateSessionDevice(session, identity);
    await _sessions.write(session);
    return AuthCompletion(session: session, exportKey: pakeFinish.exportKey);
  }

  Future<AuthSession?> refresh() async {
    final existing = await _sessions.read();
    if (existing == null) return null;
    final refreshed = AuthSession.fromJson(
      await _transport.post(
        '/auth/refresh',
        data: {'refresh_token': existing.refreshToken},
      ),
    );
    if (refreshed.account.accountId != existing.account.accountId ||
        refreshed.device.deviceId != existing.device.deviceId) {
      await _sessions.clear();
      throw const FormatException('Refreshed session identity changed');
    }
    await _sessions.write(refreshed);
    return refreshed;
  }

  Future<void> revoke() async {
    final existing = await _sessions.read();
    if (existing == null) return;
    try {
      await _transport.post('/auth/revoke');
    } finally {
      await _sessions.clear();
    }
  }

  void _validateProtocol(_AuthStart start) {
    if (start.protocol != _pake.protocol ||
        start.protocolVersion != _pake.protocolVersion) {
      throw FormatException(
        'PAKE protocol mismatch: ${start.protocol} v${start.protocolVersion}',
      );
    }
  }

  void _validateSessionDevice(AuthSession session, DeviceIdentity identity) {
    if (session.device.deviceId != identity.deviceId ||
        session.device.publicKey != identity.publicKey ||
        session.device.trustState != DeviceTrustState.trusted) {
      throw const FormatException(
        'Server returned unexpected device enrollment',
      );
    }
  }
}

class _AuthStart {
  final String protocol;
  final int protocolVersion;
  final String flowId;
  final String serverResponse;

  const _AuthStart({
    required this.protocol,
    required this.protocolVersion,
    required this.flowId,
    required this.serverResponse,
  });

  factory _AuthStart.fromJson(Map<String, dynamic> json) => _AuthStart(
    protocol: _requiredString(json, 'protocol'),
    protocolVersion: _requiredInt(json, 'protocol_version'),
    flowId: _requiredString(json, 'flow_id'),
    serverResponse: _requiredString(json, 'server_response'),
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string for $key');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value > 0) return value;
  throw FormatException('Expected positive integer for $key');
}
