import 'dart:convert';

import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_resolver.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/app/theme/theme_tokens.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixtureCopy() {
  return jsonDecode(jsonEncode(liflyTestThemePackageJson))
      as Map<String, dynamic>;
}

void main() {
  test('valid declarative package parses semantic manifest and tokens', () {
    final package = ThemePackage.fromJson(_fixtureCopy());

    expect(package.manifest.themeId, 'lifly.test.mint');
    expect(package.manifest.version, '1.0.0');
    expect(package.manifest.minimumAppVersion, '0.8.0');
    expect(package.manifest.supportedPlatforms, {
      ThemeTargetPlatform.web,
      ThemeTargetPlatform.phone,
      ThemeTargetPlatform.desktop,
    });
    expect(package.manifest.supportedColorModes, {
      ThemePackageColorMode.light,
      ThemePackageColorMode.dark,
    });
    expect(package.manifest.performanceClass, ThemePerformanceClass.standard);
    expect(package.manifest.entitlementType, ThemeEntitlementType.free);
    expect(package.manifest.fallbackThemeId, LiflyCoreTheme.familyId);
    expect(package.tokens.light.spacing.page, 20);
    expect(package.tokens.dark.motion.normal.inMilliseconds, 180);
  });

  test(
    'package resolver produces an applicable non-Core theme snapshot',
    () async {
      final package = ThemePackage.fromJson(_fixtureCopy());
      final resolver = ThemePackageResolver(
        package: package,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      );

      final snapshot = await resolver.resolve();

      expect(snapshot.familyId, 'lifly.test.mint');
      expect(snapshot.packageVersion, '1.0.0');
      expect(snapshot.performanceClass, ThemePerformanceClass.standard);
      expect(snapshot.themeMode, ThemeMode.system);
      expect(snapshot.lightTheme.colorScheme.primary, const Color(0xFF176B52));
      expect(snapshot.darkTheme.colorScheme.primary, const Color(0xFF8DD8BC));
      expect(snapshot.lightTheme.cardTheme.elevation, 1);
    },
  );

  test('manifest rejects executable fields and unsafe asset paths', () {
    final executable = _fixtureCopy();
    final executableManifest = executable['manifest'] as Map<String, dynamic>;
    executableManifest['dart_entrypoint'] = 'package:evil/theme.dart';

    expect(
      () => ThemePackage.fromJson(executable),
      throwsA(isA<ThemePackageFormatException>()),
    );

    final nestedExecutable = _fixtureCopy();
    final nestedTokens = nestedExecutable['tokens'] as Map<String, dynamic>;
    final nestedLight = nestedTokens['light'] as Map<String, dynamic>;
    nestedLight['script'] = 'stealUserData()';

    expect(
      () => ThemePackage.fromJson(nestedExecutable),
      throwsA(isA<ThemePackageFormatException>()),
    );

    final traversal = _fixtureCopy();
    final traversalManifest = traversal['manifest'] as Map<String, dynamic>;
    final assets = traversalManifest['assets'] as List<dynamic>;
    (assets.first as Map<String, dynamic>)['path'] = '../outside.png';

    expect(
      () => ThemePackage.fromJson(traversal),
      throwsA(isA<ThemePackageFormatException>()),
    );
  });

  test('manifest rejects missing required fields and untrusted signers', () {
    final missingField = _fixtureCopy();
    final missingManifest = missingField['manifest'] as Map<String, dynamic>;
    missingManifest.remove('author');

    expect(
      () => ThemePackage.fromJson(missingField),
      throwsA(isA<ThemePackageFormatException>()),
    );

    final untrusted = _fixtureCopy();
    final untrustedManifest = untrusted['manifest'] as Map<String, dynamic>;
    final integrity = untrustedManifest['integrity'] as Map<String, dynamic>;
    integrity['signer'] = 'third.party';

    expect(
      () => ThemePackage.fromJson(untrusted),
      throwsA(isA<ThemePackageFormatException>()),
    );
  });

  test('resolver rejects incompatible app versions and platforms', () async {
    final package = ThemePackage.fromJson(_fixtureCopy());

    await expectLater(
      ThemePackageResolver(
        package: package,
        appVersion: '0.7.9',
        platform: ThemeTargetPlatform.web,
      ).resolve(),
      throwsA(isA<ThemePackageCompatibilityException>()),
    );

    final webOnlyJson = _fixtureCopy();
    final manifest = webOnlyJson['manifest'] as Map<String, dynamic>;
    manifest['supported_platforms'] = ['web'];
    final webOnlyPackage = ThemePackage.fromJson(webOnlyJson);

    await expectLater(
      ThemePackageResolver(
        package: webOnlyPackage,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.phone,
      ).resolve(),
      throwsA(isA<ThemePackageCompatibilityException>()),
    );
  });

  test('runtime falls back to Core when package compatibility fails', () async {
    final runtime = ThemeRuntime(
      resolver: ThemePackageResolver(
        package: ThemePackage.fromJson(_fixtureCopy()),
        appVersion: '0.7.9',
        platform: ThemeTargetPlatform.web,
      ),
    );

    await runtime.restore();

    expect(runtime.snapshot.familyId, LiflyCoreTheme.familyId);
    expect(runtime.lastRestoreError, isA<ThemePackageCompatibilityException>());
  });

  test('invalid token ranges are rejected', () {
    final json = _fixtureCopy();
    final tokens = json['tokens'] as Map<String, dynamic>;
    final light = tokens['light'] as Map<String, dynamic>;
    final spacing = light['spacing'] as Map<String, dynamic>;
    spacing['page'] = 1000;

    expect(
      () => ThemePackage.fromJson(json),
      throwsA(isA<ThemeTokenFormatException>()),
    );
  });

  test('unknown optional token values do not change required semantics', () {
    final json = _fixtureCopy();
    final tokens = json['tokens'] as Map<String, dynamic>;
    final light = tokens['light'] as Map<String, dynamic>;
    light['experimental_glow'] = {'strength': 0.5};

    final package = ThemePackage.fromJson(json);

    expect(package.tokens.light.colors.critical, const Color(0xFFBA1A1A));
    expect(package.tokens.light.spacing.page, 20);
  });
}
