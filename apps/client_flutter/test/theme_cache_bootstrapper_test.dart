import 'dart:convert';

import 'package:client_flutter/app/theme/theme_cache_bootstrapper.dart';
import 'package:client_flutter/app/theme/theme_entitlement.dart';
import 'package:client_flutter/app/theme/theme_integrity.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_bundle.dart';
import 'package:client_flutter/app/theme/theme_package_cache.dart';
import 'package:client_flutter/app/theme/theme_package_store.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_registry.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryPreferenceStore implements ThemePreferenceStore {
  ThemePreference? value;

  _MemoryPreferenceStore(this.value);

  @override
  Future<ThemePreference?> load() async => value;

  @override
  Future<void> save(ThemePreference preference) async {
    value = preference;
  }
}

ThemePackageBundle _signedFixture() {
  final json =
      jsonDecode(jsonEncode(liflyTestThemePackageJson)) as Map<String, dynamic>;
  final manifest = json['manifest'] as Map<String, dynamic>;
  final integrity = manifest['integrity'] as Map<String, dynamic>;
  integrity['digest'] = '0' * 64;
  integrity['signature'] = 'pending';
  final digest = ThemePackageBundle.computeCanonicalDigest(json);
  integrity['digest'] = digest;
  integrity['signature'] = 'sig:$digest';
  return ThemePackageBundle(packageJson: json);
}

void main() {
  test(
    'cached known-good theme activates only after Core is available',
    () async {
      final cache = MemoryThemePackageCache();
      final verifier = ThemePackageIntegrityVerifier(
        signatureVerifier: const LocalThemeSignatureVerifier(),
      );
      final entitlements = LocalThemeEntitlementProvider();
      await ThemePackageStore(
        cache: cache,
        integrityVerifier: verifier,
        entitlementProvider: entitlements,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      ).installAndActivate(_signedFixture());

      final registry = ThemeRegistry();
      final runtime = ThemeRuntime(
        registry: registry,
        preferenceStore: _MemoryPreferenceStore(
          const ThemePreference(
            familyId: 'lifly.test.mint',
            colorMode: ThemePackageColorMode.dark,
          ),
        ),
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      );

      expect(runtime.snapshot.familyId, 'lifly.core');

      final cached = await ThemeCacheBootstrapper(
        cache: cache,
        integrityVerifier: verifier,
        entitlementProvider: entitlements,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      ).load();
      registry.registerPackages(cached.packages);
      await runtime.restore();

      expect(cached.packages.single.manifest.themeId, 'lifly.test.mint');
      expect(runtime.snapshot.familyId, 'lifly.test.mint');
      expect(runtime.snapshot.themeMode.name, 'dark');
    },
  );

  test('invalid cached package is skipped without blocking Core', () async {
    final cache = MemoryThemePackageCache();
    final bundle = _signedFixture();
    final corrupt =
        jsonDecode(jsonEncode(bundle.packageJson)) as Map<String, dynamic>;
    final manifest = corrupt['manifest'] as Map<String, dynamic>;
    final integrity = manifest['integrity'] as Map<String, dynamic>;
    integrity['digest'] = 'f' * 64;
    final corruptBundle = ThemePackageBundle(packageJson: corrupt);
    await cache.writeVersion(corruptBundle);
    await cache.activateVersion(corruptBundle.themeId, corruptBundle.version);

    final result = await ThemeCacheBootstrapper(
      cache: cache,
      integrityVerifier: ThemePackageIntegrityVerifier(
        signatureVerifier: const LocalThemeSignatureVerifier(),
      ),
      entitlementProvider: LocalThemeEntitlementProvider(),
      appVersion: '0.8.0',
      platform: ThemeTargetPlatform.web,
    ).load();

    expect(result.packages, isEmpty);
    expect(result.diagnostics, isNotEmpty);
  });
}
