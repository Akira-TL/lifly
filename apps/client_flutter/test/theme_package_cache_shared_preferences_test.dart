import 'dart:convert';

import 'package:client_flutter/app/theme/theme_package_bundle.dart';
import 'package:client_flutter/app/theme/theme_package_cache_shared_preferences.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Map<String, dynamic> _bundleJson(String version) {
  final json =
      jsonDecode(jsonEncode(liflyTestThemePackageJson)) as Map<String, dynamic>;
  final manifest = json['manifest'] as Map<String, dynamic>;
  manifest['version'] = version;
  return json;
}

void main() {
  test('key-value cache preserves versions and active pointer', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
    final first = SharedPreferencesThemePackageCache();
    await first.writeVersion(
      ThemePackageBundle(packageJson: _bundleJson('1.0.0')),
    );
    await first.writeVersion(
      ThemePackageBundle(packageJson: _bundleJson('2.0.0')),
    );
    await first.activateVersion('lifly.test.mint', '2.0.0');

    final reopened = SharedPreferencesThemePackageCache();
    final active = await reopened.readActiveVersion('lifly.test.mint');
    final versions = await reopened.listVersions('lifly.test.mint');
    final bundle = await reopened.readVersion('lifly.test.mint', active!);

    expect(active, '2.0.0');
    expect(versions, containsAll(<String>['1.0.0', '2.0.0']));
    expect(bundle?.version, '2.0.0');
  });

  test('key-value cache rejects unsafe identifiers', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
    final cache = SharedPreferencesThemePackageCache();

    await expectLater(
      cache.readVersion('../outside', '1.0.0'),
      throwsA(isA<Exception>()),
    );
  });
}
