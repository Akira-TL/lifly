import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StaticThemeResolver implements ThemeResolver {
  ThemeSnapshot? nextSnapshot;
  Object? nextError;

  _StaticThemeResolver({this.nextSnapshot});

  @override
  Future<ThemeSnapshot?> resolve() async {
    final error = nextError;
    if (error != null) throw error;
    return nextSnapshot;
  }
}

void main() {
  test('ThemeRuntime exposes Lifly Core synchronously before restoration', () {
    final runtime = ThemeRuntime();

    expect(runtime.snapshot.familyId, LiflyCoreTheme.familyId);
    expect(runtime.snapshot.displayName, 'Lifly Core');
    expect(runtime.snapshot.themeMode, ThemeMode.system);
    expect(runtime.snapshot.lightTheme.brightness, Brightness.light);
    expect(runtime.snapshot.darkTheme.brightness, Brightness.dark);
  });

  test(
    'ThemeRuntime restores a resolved theme and falls back to Core on error',
    () async {
      final resolvedSnapshot = ThemeSnapshot(
        familyId: 'test.theme',
        displayName: '测试主题',
        packageVersion: '1.0.0',
        performanceClass: ThemePerformanceClass.standard,
        tokens: LiflyCoreTheme.tokens,
        lightTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorSchemeSeed: Colors.teal,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.teal,
        ),
        themeMode: ThemeMode.dark,
      );
      final resolver = _StaticThemeResolver(nextSnapshot: resolvedSnapshot);
      final runtime = ThemeRuntime(resolver: resolver);

      await runtime.restore();
      expect(runtime.snapshot, same(resolvedSnapshot));

      resolver
        ..nextSnapshot = null
        ..nextError = StateError('theme package is invalid');
      await runtime.restore();

      expect(runtime.snapshot.familyId, LiflyCoreTheme.familyId);
      expect(runtime.lastRestoreError, isA<StateError>());
    },
  );
}
