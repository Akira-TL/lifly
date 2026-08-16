import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/account_runtime_state.dart';
import 'package:client_flutter/data/auth/auth_repository.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/pake_client_adapter.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/crypto/account_e2ee_runtime.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
import 'package:client_flutter/data/device/device_repository.dart';
import 'package:client_flutter/data/powersync/powersync_connection_coordinator.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AccountDeviceSnapshot {
  final AuthSession? session;
  final List<DeviceDescriptor> devices;
  final AccountRuntimeState runtimeState;

  const AccountDeviceSnapshot({
    this.session,
    this.devices = const [],
    this.runtimeState = const AccountRuntimeState.signedOut(),
  });

  String? get currentDeviceId => session?.device.deviceId;
}

abstract interface class AccountDeviceRuntime {
  bool get passwordAuthAvailable;

  Future<AccountDeviceSnapshot> load();

  Future<AccountRuntimeState> resolveRuntimeState();

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

  /// Local sign-out only. Does not revoke the server session or Device.
  Future<AccountDeviceSnapshot> logout();

  /// Revokes the current server session, then clears local Account data.
  Future<AccountDeviceSnapshot> revokeSession();

  Future<AccountDeviceSnapshot> renameDevice(
    String deviceId,
    String displayName,
  );

  Future<AccountDeviceSnapshot> setDefaultComputeNode(String deviceId);

  Future<AccountDeviceSnapshot> revokeDevice(String deviceId);

  /// Destroys the local Device Key after the Account session is signed out.
  Future<void> destroyLocalDeviceIdentity();
}

class DefaultAccountDeviceRuntime implements AccountDeviceRuntime {
  final AuthSessionStore _sessions;
  final AuthRepository _auth;
  final DeviceRepository _devices;
  final AccountE2eeRuntime? _e2ee;
  final PowerSyncConnectionCoordinator? _syncCoordinator;
  final bool _passwordAuthAvailable;

  DefaultAccountDeviceRuntime(
    ApiClient api, {
    PakeClientAdapter? pake,
    SecretStore? secrets,
    AuthSessionStore? sessions,
    DeviceIdentityStore? deviceIdentity,
    DeviceClientProfile? deviceProfile,
    DeviceRepository? devices,
    AccountE2eeRuntime? e2ee,
    PowerSyncConnectionCoordinator? syncCoordinator,
  }) : this._(
         api,
         pake ?? defaultPakeClientAdapter(),
         secrets ?? FlutterSecureSecretStore(),
         sessions,
         deviceIdentity,
         deviceProfile,
         devices,
         e2ee,
         syncCoordinator,
       );

  DefaultAccountDeviceRuntime._(
    ApiClient api,
    PakeClientAdapter pake,
    SecretStore secrets,
    AuthSessionStore? sessions,
    DeviceIdentityStore? deviceIdentity,
    DeviceClientProfile? deviceProfile,
    DeviceRepository? devices,
    AccountE2eeRuntime? e2ee,
    PowerSyncConnectionCoordinator? syncCoordinator,
  ) : _sessions = sessions ?? SecureAuthSessionStore(secrets),
      _e2ee = e2ee,
      _syncCoordinator = syncCoordinator,
      _passwordAuthAvailable = pake is! UnavailableOpaqueClientAdapter,
      _devices = devices ?? DeviceRepository(ApiClientDeviceTransport(api)),
      _auth = AuthRepository(
        ApiClientAuthTransport(
          api,
          sessions ?? SecureAuthSessionStore(secrets),
        ),
        sessions ?? SecureAuthSessionStore(secrets),
        deviceIdentity ?? SecureDeviceIdentityStore(secrets),
        pake,
        deviceProfile ?? _defaultDeviceProfile(),
      );

  @override
  bool get passwordAuthAvailable => _passwordAuthAvailable;

  @override
  Future<AccountRuntimeState> resolveRuntimeState() async =>
      (await load()).runtimeState;

  @override
  Future<AccountDeviceSnapshot> load() async {
    final session = await _sessions.read();
    if (session == null) return const AccountDeviceSnapshot();

    final e2ee = _e2ee;
    if (e2ee == null) {
      return _snapshot(
        session,
        phase: AccountRuntimePhase.degraded,
        dataUnlocked: false,
        detail: 'Account E2EE runtime is unavailable',
      );
    }
    if (e2ee.isUnlocking) {
      return _snapshot(
        session,
        phase: AccountRuntimePhase.unlocking,
        dataUnlocked: false,
      );
    }
    if (!e2ee.isUnlocked) {
      return _snapshot(
        session,
        phase: e2ee.lastUnlockError == null
            ? AccountRuntimePhase.authenticatedLocked
            : AccountRuntimePhase.degraded,
        dataUnlocked: false,
        detail: e2ee.lastUnlockError,
      );
    }

    var devices = const <DeviceDescriptor>[];
    String? degradedDetail;
    try {
      devices = await _devices.list();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _clearLocalAccountData();
        await _auth.clearSession();
        return const AccountDeviceSnapshot();
      }
      degradedDetail = 'Device Registry unavailable: $error';
    } catch (error) {
      degradedDetail = 'Device Registry unavailable: $error';
    }

    final coordinator = _syncCoordinator;
    if (coordinator == null) {
      degradedDetail ??= 'PowerSync coordinator is unavailable';
    } else {
      if (!coordinator.diagnostics.isConnected) {
        await coordinator.connect();
      }
      final diagnostics = coordinator.diagnostics;
      if (!diagnostics.isConnected) {
        degradedDetail ??=
            'PowerSync ${diagnostics.status}: ${diagnostics.error ?? 'offline'}';
      }
    }

    return _snapshot(
      session,
      devices: devices,
      phase: degradedDetail == null
          ? AccountRuntimePhase.ready
          : AccountRuntimePhase.degraded,
      dataUnlocked: true,
      detail: degradedDetail,
    );
  }

  @override
  Future<AccountDeviceSnapshot> register({
    required String phone,
    required String password,
    String? displayName,
  }) async {
    _requirePasswordAuth();
    final completion = await _auth.register(
      phone: phone,
      password: password,
      displayName: displayName,
    );
    try {
      final e2ee = _requireE2ee();
      await e2ee.initializeAfterRegistration(completion);
    } catch (_) {
      await _e2ee?.destroyLocalKeyForCurrentSession();
      await _auth.clearSession();
      rethrow;
    }
    return load();
  }

  @override
  Future<AccountDeviceSnapshot> login({
    required String phone,
    required String password,
  }) async {
    _requirePasswordAuth();
    final completion = await _auth.login(phone: phone, password: password);
    try {
      final e2ee = _requireE2ee();
      await e2ee.initializeAfterLogin(completion);
    } catch (_) {
      await _e2ee?.destroyLocalKeyForCurrentSession();
      await _auth.clearSession();
      rethrow;
    }
    return load();
  }

  @override
  Future<AccountDeviceSnapshot> refreshSession() async {
    try {
      await _auth.refresh();
    } on FormatException {
      await _clearLocalAccountData();
      rethrow;
    }
    return load();
  }

  @override
  Future<AccountDeviceSnapshot> logout() async {
    await _clearLocalAccountData();
    await _auth.clearSession();
    return const AccountDeviceSnapshot();
  }

  @override
  Future<AccountDeviceSnapshot> revokeSession() async {
    await _auth.revokeRemoteSession();
    await _clearLocalAccountData();
    await _auth.clearSession();
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
    final revokingCurrentDevice = session?.device.deviceId == deviceId;
    await _devices.revoke(deviceId);
    if (revokingCurrentDevice) {
      await _clearLocalAccountData();
      await _auth.clearSession();
      return const AccountDeviceSnapshot();
    }
    return load();
  }

  @override
  Future<void> destroyLocalDeviceIdentity() async {
    if (await _sessions.read() != null) {
      throw StateError('Sign out before destroying the local Device identity');
    }
    await _auth.destroyDeviceIdentity();
  }

  Future<void> _clearLocalAccountData() async {
    await _e2ee?.destroyLocalKeyForCurrentSession();
    await _syncCoordinator?.disconnect(clearLocal: true);
  }

  AccountE2eeRuntime _requireE2ee() {
    final e2ee = _e2ee;
    if (e2ee == null) {
      throw StateError('Account E2EE runtime is unavailable');
    }
    return e2ee;
  }

  AccountDeviceSnapshot _snapshot(
    AuthSession session, {
    List<DeviceDescriptor> devices = const [],
    required AccountRuntimePhase phase,
    required bool dataUnlocked,
    String? detail,
  }) => AccountDeviceSnapshot(
    session: session,
    devices: devices,
    runtimeState: AccountRuntimeState(
      phase: phase,
      session: session,
      dataUnlocked: dataUnlocked,
      detail: detail,
    ),
  );

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
