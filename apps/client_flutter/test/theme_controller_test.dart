import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_registry.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryThemePreferenceStore implements ThemePreferenceStore {
  ThemePreference? value;
  int saveCount = 0;

  _MemoryThemePreferenceStore([this.value]);

  @override
  Future<ThemePreference?> load() async => value;

  @override
  Future<void> save(ThemePreference preference) async {
    value = preference;
    saveCount += 1;
  }
}

ThemeRegistry _registry() {
  return ThemeRegistry(
    packages: [ThemePackage.fromJson(liflyTestThemePackageJson)],
  );
}

void main() {
  test('registry exposes Core and installed declarative theme families', () {
    final registry = _registry();

    expect(
      registry.installedThemes.map((theme) => theme.familyId),
      containsAll(<String>[LiflyCoreTheme.familyId, 'lifly.test.mint']),
    );
    expect(registry.installedThemes.first.isCore, isTrue);
  });

  test('runtime restores a persisted family and device color mode', () async {
    final store = _MemoryThemePreferenceStore(
      const ThemePreference(
        familyId: 'lifly.test.mint',
        colorMode: ThemePackageColorMode.dark,
      ),
    );
    final runtime = ThemeRuntime(
      registry: _registry(),
      preferenceStore: store,
      appVersion: '0.8.0',
      platform: ThemeTargetPlatform.web,
    );

    expect(runtime.snapshot.familyId, LiflyCoreTheme.familyId);
    await runtime.restore();

    expect(runtime.preference.familyId, 'lifly.test.mint');
    expect(runtime.preference.colorMode, ThemePackageColorMode.dark);
    expect(runtime.snapshot.familyId, 'lifly.test.mint');
    expect(runtime.snapshot.themeMode, ThemeMode.dark);
  });

  test('selecting a family and color mode persists both values', () async {
    final store = _MemoryThemePreferenceStore();
    final runtime = ThemeRuntime(
      registry: _registry(),
      preferenceStore: store,
      appVersion: '0.8.0',
      platform: ThemeTargetPlatform.phone,
    );

    await runtime.selectFamily('lifly.test.mint');
    await runtime.selectColorMode(ThemePackageColorMode.light);

    expect(runtime.snapshot.familyId, 'lifly.test.mint');
    expect(runtime.snapshot.themeMode, ThemeMode.light);
    expect(
      store.value,
      const ThemePreference(
        familyId: 'lifly.test.mint',
        colorMode: ThemePackageColorMode.light,
      ),
    );
    expect(store.saveCount, 2);
  });

  test('unsupported reserved modes degrade deterministically', () async {
    final store = _MemoryThemePreferenceStore();
    final runtime = ThemeRuntime(
      registry: _registry(),
      preferenceStore: store,
      appVersion: '0.8.0',
      platform: ThemeTargetPlatform.desktop,
    );

    await runtime.selectFamily('lifly.test.mint');
    await runtime.selectColorMode(ThemePackageColorMode.oled);

    expect(runtime.preference.colorMode, ThemePackageColorMode.oled);
    expect(runtime.resolvedColorMode, ThemePackageColorMode.dark);
    expect(runtime.snapshot.themeMode, ThemeMode.dark);

    await runtime.selectColorMode(ThemePackageColorMode.highContrast);

    expect(runtime.resolvedColorMode, ThemePackageColorMode.light);
    expect(runtime.snapshot.themeMode, ThemeMode.light);
  });

  test(
    'unknown installed family falls back to Core without losing access',
    () async {
      final store = _MemoryThemePreferenceStore(
        const ThemePreference(
          familyId: 'missing.theme',
          colorMode: ThemePackageColorMode.dark,
        ),
      );
      final runtime = ThemeRuntime(
        registry: _registry(),
        preferenceStore: store,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      );

      await runtime.restore();

      expect(runtime.snapshot.familyId, LiflyCoreTheme.familyId);
      expect(runtime.preference.familyId, LiflyCoreTheme.familyId);
      expect(runtime.lastRestoreError, isNotNull);
    },
  );
}
