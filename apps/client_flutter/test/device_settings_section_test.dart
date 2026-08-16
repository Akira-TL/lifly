import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/account_runtime_state.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/features/settings/account_device_runtime.dart';
import 'package:client_flutter/features/settings/widgets/account_device_settings_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRuntime implements AccountDeviceRuntime {
  AccountDeviceSnapshot snapshot;
  @override
  final bool passwordAuthAvailable;
  String? selectedDefault;
  Object? registerError;
  int localLogoutCalls = 0;
  int revokeSessionCalls = 0;
  int destroyIdentityCalls = 0;

  _FakeRuntime({
    required this.snapshot,
    this.passwordAuthAvailable = true,
    this.registerError,
  });

  @override
  Future<AccountDeviceSnapshot> load() async => snapshot;

  @override
  Future<AccountRuntimeState> resolveRuntimeState() async =>
      snapshot.runtimeState;

  @override
  Future<void> destroyLocalDeviceIdentity() async {
    destroyIdentityCalls += 1;
  }

  @override
  Future<AccountDeviceSnapshot> revokeSession() async {
    revokeSessionCalls += 1;
    snapshot = const AccountDeviceSnapshot();
    return snapshot;
  }

  @override
  Future<AccountDeviceSnapshot> login({
    required String phone,
    required String password,
  }) async => snapshot;

  @override
  Future<AccountDeviceSnapshot> logout() async {
    localLogoutCalls += 1;
    snapshot = const AccountDeviceSnapshot();
    return snapshot;
  }

  @override
  Future<AccountDeviceSnapshot> refreshSession() async => snapshot;

  @override
  Future<AccountDeviceSnapshot> register({
    required String phone,
    required String password,
    String? displayName,
  }) async {
    final error = registerError;
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<AccountDeviceSnapshot> renameDevice(
    String deviceId,
    String displayName,
  ) async => snapshot;

  @override
  Future<AccountDeviceSnapshot> revokeDevice(String deviceId) async => snapshot;

  @override
  Future<AccountDeviceSnapshot> setDefaultComputeNode(String deviceId) async {
    selectedDefault = deviceId;
    return snapshot;
  }
}

DeviceDescriptor _device({
  required String id,
  required String name,
  bool isDefault = false,
}) => DeviceDescriptor(
  deviceId: id,
  accountId: 'account-1',
  displayName: name,
  platform: id == 'phone-1' ? 'android' : 'linux',
  publicKey: 'public-$id',
  trustState: DeviceTrustState.trusted,
  capabilityReport: id == 'desktop-1'
      ? const DeviceCapabilityReport(
          capabilities: [DeviceCapability.localAi, DeviceCapability.localMcp],
        )
      : const DeviceCapabilityReport(),
  isDefaultComputeNode: isDefault,
);

AccountDeviceSnapshot _signedInSnapshot() {
  final phone = _device(id: 'phone-1', name: 'Phone');
  final desktop = _device(id: 'desktop-1', name: 'Desktop');
  final session = AuthSession(
    account: const AccountProfile(
      accountId: 'account-1',
      phoneE164: '+8613800138000',
      displayName: 'Demo',
      accountStatus: 'active',
      plan: 'demo',
    ),
    device: phone,
    accessToken: 'access',
    refreshToken: 'refresh',
    accessExpiresAt: DateTime.utc(2026, 8, 16),
    refreshExpiresAt: DateTime.utc(2026, 9, 15),
  );
  return AccountDeviceSnapshot(
    session: session,
    devices: [phone, desktop],
    runtimeState: AccountRuntimeState(
      phase: AccountRuntimePhase.ready,
      session: session,
      dataUnlocked: true,
    ),
  );
}

void main() {
  testWidgets(
    'signed out state disables password auth when PAKE bridge is absent',
    (tester) async {
      final runtime = _FakeRuntime(
        snapshot: const AccountDeviceSnapshot(),
        passwordAuthAvailable: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountDeviceSettingsSection(
              api: ApiClient(baseUrl: 'http://invalid'),
              runtime: runtime,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pake-unavailable')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('account-register')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('account-login')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'registration conflict shows actionable message instead of raw DioException',
    (tester) async {
      final request = RequestOptions(path: '/auth/register/start');
      final runtime = _FakeRuntime(
        snapshot: const AccountDeviceSnapshot(),
        registerError: DioException.badResponse(
          statusCode: 409,
          requestOptions: request,
          response: Response<dynamic>(
            requestOptions: request,
            statusCode: 409,
            data: {'detail': 'Phone already registered'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountDeviceSettingsSection(
              api: ApiClient(baseUrl: 'http://invalid'),
              runtime: runtime,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '13800138000');
      await tester.enterText(find.byType(TextField).at(1), 'secret-password');
      await tester.tap(find.byKey(const ValueKey('account-register')));
      await tester.pumpAndSettle();

      expect(find.text('该手机号已注册，请直接登录。'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
    },
  );

  testWidgets('signed in state shows devices and default compute action', (
    tester,
  ) async {
    final runtime = _FakeRuntime(snapshot: _signedInSnapshot());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountDeviceSettingsSection(
              api: ApiClient(baseUrl: 'http://invalid'),
              runtime: runtime,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+8613800138000'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Desktop'), findsOneWidget);
    expect(find.textContaining('已信任'), findsWidgets);
    expect(find.textContaining('本地 AI'), findsOneWidget);
    expect(find.textContaining('本地 MCP'), findsOneWidget);
    expect(find.textContaining('local_ai'), findsNothing);
    expect(find.textContaining('trusted'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('default-desktop-1')));
    await tester.pumpAndSettle();
    expect(runtime.selectedDefault, 'desktop-1');
  });

  testWidgets(
    'logout, session revoke, device revoke, and identity reset are distinct controls',
    (tester) async {
      Future<void> pumpRuntime(_FakeRuntime runtime) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AccountDeviceSettingsSection(
                  key: UniqueKey(),
                  api: ApiClient(baseUrl: 'http://invalid'),
                  runtime: runtime,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      final logoutRuntime = _FakeRuntime(snapshot: _signedInSnapshot());
      await pumpRuntime(logoutRuntime);
      expect(find.byKey(const ValueKey('local-logout')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('revoke-current-session')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('revoke-phone-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('local-logout')));
      await tester.pumpAndSettle();
      expect(logoutRuntime.localLogoutCalls, 1);
      expect(logoutRuntime.revokeSessionCalls, 0);

      final revokeRuntime = _FakeRuntime(snapshot: _signedInSnapshot());
      await pumpRuntime(revokeRuntime);
      await tester.tap(find.byKey(const ValueKey('revoke-current-session')));
      await tester.pumpAndSettle();
      expect(revokeRuntime.revokeSessionCalls, 1);
      expect(revokeRuntime.localLogoutCalls, 0);

      final resetRuntime = _FakeRuntime(
        snapshot: const AccountDeviceSnapshot(),
      );
      await pumpRuntime(resetRuntime);
      await tester.tap(
        find.byKey(const ValueKey('destroy-local-device-identity')),
      );
      await tester.pumpAndSettle();
      expect(find.text('重置此设备身份？'), findsOneWidget);
      await tester.tap(find.text('重置身份'));
      await tester.pumpAndSettle();
      expect(resetRuntime.destroyIdentityCalls, 1);
    },
  );
}
