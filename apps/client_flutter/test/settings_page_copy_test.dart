import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_registry.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/account_runtime_state.dart';
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeRuntime>.value(value: runtime),
          Provider<ApiClient>.value(
            value: ApiClient(baseUrl: 'http://localhost/api/v1'),
          ),
          Provider<LiflyDataMode>.value(value: LiflyDataMode.local),
          Provider<AccountDeviceRuntime>.value(
            value: _StubAccountDeviceRuntime(),
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
}
