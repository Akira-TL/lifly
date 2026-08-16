import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_registry.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/account_runtime_state.dart';
import 'package:client_flutter/data/powersync/powersync_connection_coordinator.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/sync_push_service.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:client_flutter/features/settings/account_device_runtime.dart';
import 'package:client_flutter/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubAccountDeviceRuntime implements AccountDeviceRuntime {
  @override
  bool get passwordAuthAvailable => false;

  @override
  Future<AccountDeviceSnapshot> load() async => const AccountDeviceSnapshot();

  @override
  Future<AccountRuntimeState> resolveRuntimeState() async =>
      const AccountRuntimeState.signedOut();

  @override
  Future<void> destroyLocalDeviceIdentity() async {}

  @override
  Future<AccountDeviceSnapshot> revokeSession() async =>
      const AccountDeviceSnapshot();

  @override
  Future<AccountDeviceSnapshot> login({
    required String phone,
    required String password,
  }) async => const AccountDeviceSnapshot();

  @override
  Future<AccountDeviceSnapshot> logout() async => const AccountDeviceSnapshot();

  @override
  Future<AccountDeviceSnapshot> refreshSession() async =>
      const AccountDeviceSnapshot();

  @override
  Future<AccountDeviceSnapshot> register({
    required String phone,
    required String password,
    String? displayName,
  }) async => const AccountDeviceSnapshot();

  @override
  Future<AccountDeviceSnapshot> renameDevice(
    String deviceId,
    String displayName,
  ) async => const AccountDeviceSnapshot();

  @override
  Future<AccountDeviceSnapshot> revokeDevice(String deviceId) async =>
      const AccountDeviceSnapshot();

  @override
  Future<AccountDeviceSnapshot> setDefaultComputeNode(String deviceId) async =>
      const AccountDeviceSnapshot();
}

class _PresetSyncService extends SyncService {
  final SyncPushUploadDiagnostics presetUploadDiagnostics;

  _PresetSyncService(this.presetUploadDiagnostics)
    : super(api: ApiClient(baseUrl: 'http://localhost/api/v1'));

  @override
  SyncPushUploadDiagnostics get uploadDiagnostics => presetUploadDiagnostics;
}

class _PresetPowerSyncCoordinator extends PowerSyncConnectionCoordinator {
  final PowerSyncConnectionDiagnostics presetDiagnostics;

  _PresetPowerSyncCoordinator({
    required super.syncService,
    required this.presetDiagnostics,
  }) : super(
         credentialsService: PowerSyncCredentialsService(
           ApiClient(baseUrl: 'http://localhost/api/v1'),
         ),
       );

  @override
  PowerSyncConnectionDiagnostics get diagnostics => presetDiagnostics;

  @override
  PowerSyncConnectionDiagnostics refreshDiagnostics() => presetDiagnostics;
}

class _MemoryThemePreferenceStore implements ThemePreferenceStore {
  @override
  Future<ThemePreference?> load() async => null;

  @override
  Future<void> save(ThemePreference preference) async {}
}

void main() {
  testWidgets('settings keeps diagnostics product-facing', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 3200);
    addTearDown(tester.view.reset);

    final runtime = ThemeRuntime(
      registry: ThemeRegistry(
        packages: [ThemePackage.fromJson(liflyTestThemePackageJson)],
      ),
      preferenceStore: _MemoryThemePreferenceStore(),
      appVersion: '0.8.2',
      platform: ThemeTargetPlatform.web,
    );

    final api = ApiClient(baseUrl: 'http://localhost/api/v1');
    final syncService = SyncService(api: api);
    final syncCoordinator = PowerSyncConnectionCoordinator(
      credentialsService: PowerSyncCredentialsService(api),
      syncService: syncService,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeRuntime>.value(value: runtime),
          Provider<ApiClient>.value(value: api),
          Provider<LiflyDataMode>.value(value: LiflyDataMode.local),
          Provider<AccountDeviceRuntime>.value(
            value: _StubAccountDeviceRuntime(),
          ),
          Provider<SyncService>.value(value: syncService),
          Provider<PowerSyncConnectionCoordinator>.value(
            value: syncCoordinator,
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('服务连接'), findsOneWidget);
    expect(find.text('数据模式'), findsOneWidget);
    expect(find.text('AI 操作记录'), findsOneWidget);
    expect(find.text('本地能力'), findsOneWidget);
    expect(find.text('数据同步'), findsOneWidget);
    expect(find.text('检查连接'), findsOneWidget);
    expect(find.text('运行完整检查'), findsOneWidget);
    expect(find.text('检查本地能力'), findsOneWidget);
    expect(find.text('连接同步'), findsOneWidget);

    for (final internalTerm in [
      'PowerSync',
      'Local Core',
      'Local MCP',
      'MCP Smoke',
      'API Base URL',
      'LIFLY_DATA_MODE',
      'uploadData',
    ]) {
      expect(find.textContaining(internalTerm), findsNothing);
    }
  });

  testWidgets('settings reflects live sync diagnostics on first open', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 3200);
    addTearDown(tester.view.reset);

    final runtime = ThemeRuntime(
      registry: ThemeRegistry(
        packages: [ThemePackage.fromJson(liflyTestThemePackageJson)],
      ),
      preferenceStore: _MemoryThemePreferenceStore(),
      appVersion: '0.9.0',
      platform: ThemeTargetPlatform.desktop,
    );
    final uploadDiagnostics = SyncPushUploadDiagnostics.success(
      at: DateTime.utc(2026, 8, 16, 12),
      uploadedChanges: 2,
      ignoredChanges: 0,
      result: const SyncPushResult(applied: 2, skipped: 0, results: []),
    );
    final credentials = LiflyPowerSyncCredentials(
      endpoint: 'https://example.test/powersync',
      token: 'token',
      userId: 'account-1',
      deviceId: 'device-1',
      expiresAt: DateTime.utc(2026, 8, 16, 13),
      mode: 'authenticated',
    );
    final connectionDiagnostics = PowerSyncConnectionDiagnostics.connected(
      at: DateTime.utc(2026, 8, 16, 12),
      credentials: credentials,
      uploadDiagnostics: uploadDiagnostics,
    );
    final syncService = _PresetSyncService(uploadDiagnostics);
    final syncCoordinator = _PresetPowerSyncCoordinator(
      syncService: syncService,
      presetDiagnostics: connectionDiagnostics,
    );
    final api = ApiClient(baseUrl: 'http://localhost/api/v1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeRuntime>.value(value: runtime),
          Provider<ApiClient>.value(value: api),
          Provider<LiflyDataMode>.value(value: LiflyDataMode.api),
          Provider<AccountDeviceRuntime>.value(
            value: _StubAccountDeviceRuntime(),
          ),
          Provider<SyncService>.value(value: syncService),
          Provider<PowerSyncConnectionCoordinator>.value(
            value: syncCoordinator,
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('https://example.test/powersync'), findsOneWidget);
    expect(find.text('account-1'), findsOneWidget);
    expect(find.text('已获取'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('成功'), findsOneWidget);
    expect(find.text('2 条业务 / 0 条忽略'), findsOneWidget);
    expect(find.text('已应用 2 条 / 已跳过 0 条'), findsOneWidget);
  });
}
