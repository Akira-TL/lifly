import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_repository.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/pake_client_adapter.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
import 'package:client_flutter/data/device/device_repository.dart';
import 'package:flutter/foundation.dart';

class AccountDeviceSnapshot {
  final AuthSession? session;
  final List<DeviceDescriptor> devices;

  const AccountDeviceSnapshot({this.session, this.devices = const []});

  String? get currentDeviceId => session?.device.deviceId;
}

abstract interface class AccountDeviceRuntime {
  bool get passwordAuthAvailable;

  Future<AccountDeviceSnapshot> load();

  Future<AccountDeviceSnapshot> register({
    required String phone,
    required String password,
    String? displayName,
  });

  Future<AccountDeviceSnapshot> login({
    required String phone,
    required String password,
  });

  Future<AccountDeviceSnapshot> refreshSession();

  Future<AccountDeviceSnapshot> logout();

  Future<AccountDeviceSnapshot> renameDevice(
    String deviceId,
    String displayName,
  );

  Future<AccountDeviceSnapshot> setDefaultComputeNode(String deviceId);

  Future<AccountDeviceSnapshot> revokeDevice(String deviceId);
}

class DefaultAccountDeviceRuntime implements AccountDeviceRuntime {
  final AuthSessionStore _sessions;
  final AuthRepository _auth;
  final DeviceRepository _devices;
  final bool _passwordAuthAvailable;

  DefaultAccountDeviceRuntime(
    ApiClient api, {
    PakeClientAdapter pake = const UnavailableOpaqueClientAdapter(),
    SecretStore? secrets,
    DeviceIdentityStore? deviceIdentity,
    DeviceClientProfile? deviceProfile,
  }) : this._(
         api,
         pake,
         secrets ?? FlutterSecureSecretStore(),
         deviceIdentity,
         deviceProfile,
       );

  DefaultAccountDeviceRuntime._(
    ApiClient api,
    PakeClientAdapter pake,
    SecretStore secrets,
    DeviceIdentityStore? deviceIdentity,
    DeviceClientProfile? deviceProfile,
  ) : _sessions = SecureAuthSessionStore(secrets),
      _passwordAuthAvailable = pake is! UnavailableOpaqueClientAdapter,
      _devices = DeviceRepository(ApiClientDeviceTransport(api)),
      _auth = AuthRepository(
        ApiClientAuthTransport(api, SecureAuthSessionStore(secrets)),
        SecureAuthSessionStore(secrets),
        deviceIdentity ?? SecureDeviceIdentityStore(secrets),
        pake,
        deviceProfile ?? _defaultDeviceProfile(),
      );

  @override
  bool get passwordAuthAvailable => _passwordAuthAvailable;

  @override
  Future<AccountDeviceSnapshot> load() async {
    final session = await _sessions.read();
    if (session == null) return const AccountDeviceSnapshot();
    return AccountDeviceSnapshot(
      session: session,
      devices: await _devices.list(),
    );
  }

  @override
  Future<AccountDeviceSnapshot> register({
    required String phone,
    required String password,
    String? displayName,
  }) async {
    _requirePasswordAuth();
    await _auth.register(
      phone: phone,
      password: password,
      displayName: displayName,
    );
    return load();
  }

  @override
  Future<AccountDeviceSnapshot> login({
    required String phone,
    required String password,
  }) async {
    _requirePasswordAuth();
    await _auth.login(phone: phone, password: password);
    return load();
  }

  @override
  Future<AccountDeviceSnapshot> refreshSession() async {
    await _auth.refresh();
    return load();
  }

  @override
  Future<AccountDeviceSnapshot> logout() async {
    await _auth.revoke();
    return const AccountDeviceSnapshot();
  }

  @override
  Future<AccountDeviceSnapshot> renameDevice(
    String deviceId,
    String displayName,
  ) async {
    await _devices.rename(deviceId, displayName);
    return load();
  }

  @override
  Future<AccountDeviceSnapshot> setDefaultComputeNode(String deviceId) async {
    await _devices.setDefaultComputeNode(deviceId);
    return load();
  }

  @override
  Future<AccountDeviceSnapshot> revokeDevice(String deviceId) async {
    final session = await _sessions.read();
    await _devices.revoke(deviceId);
    if (session?.device.deviceId == deviceId) {
      await _sessions.clear();
      return const AccountDeviceSnapshot();
    }
    return load();
  }

  void _requirePasswordAuth() {
    if (!_passwordAuthAvailable) {
      throw const PakeClientUnavailable();
    }
  }
}

DeviceClientProfile _defaultDeviceProfile() => DeviceClientProfile(
  displayName: 'Lifly ${_currentPlatform()}',
  platform: _currentPlatform(),
);

String _currentPlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}
