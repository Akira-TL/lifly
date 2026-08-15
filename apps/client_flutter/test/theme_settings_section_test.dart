import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_registry.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:client_flutter/features/settings/widgets/theme_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FailingThemePreferenceStore implements ThemePreferenceStore {
  @override
  Future<ThemePreference?> load() async => null;

  @override
  Future<void> save(ThemePreference preference) async {
    throw StateError('preferences backend leaked');
  }
}

class _MemoryThemePreferenceStore implements ThemePreferenceStore {
  ThemePreference? value;

  @override
  Future<ThemePreference?> load() async => value;

  @override
  Future<void> save(ThemePreference preference) async {
    value = preference;
  }
}

void main() {
  testWidgets('theme switch hides persistence implementation errors', (
    WidgetTester tester,
  ) async {
    final runtime = ThemeRuntime(
      registry: ThemeRegistry(
        packages: [ThemePackage.fromJson(liflyTestThemePackageJson)],
      ),
      preferenceStore: _FailingThemePreferenceStore(),
      appVersion: '0.8.0',
      platform: ThemeTargetPlatform.web,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeRuntime>.value(
        value: runtime,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ThemeSettingsSection()),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('theme_family_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mint Test').last);
    await tester.pumpAndSettle();

    expect(find.text('主题切换失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('preferences backend leaked'), findsNothing);
  });

  testWidgets('user selects an installed family and color mode', (
    WidgetTester tester,
  ) async {
    final store = _MemoryThemePreferenceStore();
    final runtime = ThemeRuntime(
      registry: ThemeRegistry(
        packages: [ThemePackage.fromJson(liflyTestThemePackageJson)],
      ),
      preferenceStore: store,
      appVersion: '0.8.0',
      platform: ThemeTargetPlatform.web,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeRuntime>.value(
        value: runtime,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ThemeSettingsSection()),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('theme_family_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mint Test').last);
    await tester.pumpAndSettle();

    expect(runtime.preference.familyId, 'lifly.test.mint');
    expect(store.value?.familyId, 'lifly.test.mint');

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(runtime.preference.colorMode, ThemePackageColorMode.dark);
    expect(runtime.snapshot.themeMode, ThemeMode.dark);
    expect(store.value?.colorMode, ThemePackageColorMode.dark);
  });

  testWidgets('unsupported reserved mode shows a compact fallback message', (
    WidgetTester tester,
  ) async {
    final runtime = ThemeRuntime(
      registry: ThemeRegistry(
        packages: [ThemePackage.fromJson(liflyTestThemePackageJson)],
      ),
      preferenceStore: _MemoryThemePreferenceStore(),
      appVersion: '0.8.0',
      platform: ThemeTargetPlatform.desktop,
    );
    await runtime.selectFamily('lifly.test.mint');
    await runtime.selectColorMode(ThemePackageColorMode.oled);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeRuntime>.value(
        value: runtime,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ThemeSettingsSection()),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('theme_color_mode_fallback')), findsOneWidget);
    expect(find.textContaining('已使用深色'), findsOneWidget);
  });
}
