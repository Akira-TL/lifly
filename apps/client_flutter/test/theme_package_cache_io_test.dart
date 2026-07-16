import 'dart:convert';
import 'dart:io';

import 'package:client_flutter/app/theme/theme_package_bundle.dart';
import 'package:client_flutter/app/theme/theme_package_cache_io.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _bundleJson(String version) {
  final json =
      jsonDecode(jsonEncode(liflyTestThemePackageJson)) as Map<String, dynamic>;
  final manifest = json['manifest'] as Map<String, dynamic>;
  manifest['version'] = version;
  return json;
}

void main() {
  test(
    'file cache preserves versions and active pointer across reopen',
    () async {
      final root = await Directory.systemTemp.createTemp('lifly-theme-cache-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final first = FileThemePackageCache(root);
      await first.writeVersion(
        ThemePackageBundle(packageJson: _bundleJson('1.0.0')),
      );
      await first.writeVersion(
        ThemePackageBundle(packageJson: _bundleJson('2.0.0')),
      );
      await first.activateVersion('lifly.test.mint', '2.0.0');

      final reopened = FileThemePackageCache(root);
      final active = await reopened.readActiveVersion('lifly.test.mint');
      final versions = await reopened.listVersions('lifly.test.mint');
      final bundle = await reopened.readVersion('lifly.test.mint', active!);

      expect(active, '2.0.0');
      expect(versions, containsAll(<String>['1.0.0', '2.0.0']));
      expect(bundle?.version, '2.0.0');
    },
  );

  test(
    'file cache recovers an interrupted active pointer replacement',
    () async {
      final root = await Directory.systemTemp.createTemp('lifly-theme-cache-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final cache = FileThemePackageCache(root);
      await cache.writeVersion(
        ThemePackageBundle(packageJson: _bundleJson('1.0.0')),
      );
      await cache.activateVersion('lifly.test.mint', '1.0.0');
      final active = File('${root.path}/lifly.test.mint/active');
      await active.rename('${active.path}.bak');

      final recovered = await FileThemePackageCache(
        root,
      ).readActiveVersion('lifly.test.mint');

      expect(recovered, '1.0.0');
      expect(await active.exists(), isTrue);
    },
  );

  test('file cache rejects path traversal identifiers', () async {
    final root = await Directory.systemTemp.createTemp('lifly-theme-cache-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final cache = FileThemePackageCache(root);

    await expectLater(
      cache.readVersion('../outside', '1.0.0'),
      throwsA(isA<Exception>()),
    );
  });
}
