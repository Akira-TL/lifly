import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/features/settings/account_device_runtime.dart';
import 'package:client_flutter/features/settings/widgets/account_device_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRuntime implements AccountDeviceRuntime {
  AccountDeviceSnapshot snapshot;
  @override
  final bool passwordAuthAvailable;
  String? selectedDefault;

  _FakeRuntime({required this.snapshot, this.passwordAuthAvailable = true});

  @override
  Future<AccountDeviceSnapshot> load() async => snapshot;

  @override
  Future<AccountDeviceSnapshot> login({
    required String phone,
    required String password,
  }) async => snapshot;

  @override
  Future<AccountDeviceSnapshot> logout() async {
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
  }) async => snapshot;

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
  return AccountDeviceSnapshot(
    session: AuthSession(
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
    ),
    devices: [phone, desktop],
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

    await tester.tap(find.byKey(const ValueKey('default-desktop-1')));
    await tester.pumpAndSettle();
    expect(runtime.selectedDefault, 'desktop-1');
  });
}
