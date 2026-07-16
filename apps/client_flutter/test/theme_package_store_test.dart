import 'dart:convert';
import 'dart:typed_data';

import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_entitlement.dart';
import 'package:client_flutter/app/theme/theme_integrity.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_bundle.dart';
import 'package:client_flutter/app/theme/theme_package_cache.dart';
import 'package:client_flutter/app/theme/theme_package_store.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _copyFixture() {
  return jsonDecode(jsonEncode(liflyTestThemePackageJson))
      as Map<String, dynamic>;
}

ThemePackageBundle _signedBundle({
  String version = '1.0.0',
  String themeId = 'lifly.test.mint',
  String fallbackThemeId = LiflyCoreTheme.familyId,
  String entitlementType = 'free',
  String signer = 'lifly.official',
}) {
  final json = _copyFixture();
  final manifest = json['manifest'] as Map<String, dynamic>;
  manifest['theme_id'] = themeId;
  manifest['version'] = version;
  manifest['fallback_theme_id'] = fallbackThemeId;
  manifest['entitlement_type'] = entitlementType;
  final integrity = manifest['integrity'] as Map<String, dynamic>;
  integrity['signer'] = signer;
  _resign(json);
  return ThemePackageBundle(packageJson: json);
}

void _resign(Map<String, dynamic> json) {
  final manifest = json['manifest'] as Map<String, dynamic>;
  final integrity = manifest['integrity'] as Map<String, dynamic>;
  integrity['digest'] = '0' * 64;
  integrity['signature'] = 'pending';
  final digest = ThemePackageBundle.computeCanonicalDigest(json);
  integrity['digest'] = digest;
  integrity['signature'] = 'sig:$digest';
}

ThemePackageStore _store({
  required MemoryThemePackageCache cache,
  required LocalThemeEntitlementProvider entitlements,
}) {
  return ThemePackageStore(
    cache: cache,
    integrityVerifier: ThemePackageIntegrityVerifier(
      signatureVerifier: const LocalThemeSignatureVerifier(),
    ),
    entitlementProvider: entitlements,
    appVersion: '0.8.0',
    platform: ThemeTargetPlatform.web,
  );
}

void main() {
  test('bundle content cannot be mutated through caller references', () {
    final source = _copyFixture();
    final assetSource = Uint8List.fromList([1, 2, 3]);
    final bundle = ThemePackageBundle(
      packageJson: source,
      assets: {'assets/test.bin': assetSource},
    );

    final sourceManifest = source['manifest'] as Map<String, dynamic>;
    sourceManifest['theme_id'] = 'mutated.source';
    assetSource[0] = 9;
    final exposed = bundle.packageJson;
    final exposedManifest = exposed['manifest'] as Map<String, dynamic>;
    exposedManifest['theme_id'] = 'mutated.exposed';
    final exposedAsset = bundle.assets['assets/test.bin']!;
    exposedAsset[0] = 8;

    expect(bundle.themeId, 'lifly.test.mint');
    expect(bundle.assetBytes('assets/test.bin'), [1, 2, 3]);
  });

  test(
    'valid package version installs and atomically becomes active',
    () async {
      final cache = MemoryThemePackageCache();
      final store = _store(
        cache: cache,
        entitlements: LocalThemeEntitlementProvider(),
      );
      final bundle = _signedBundle();

      final installed = await store.installAndActivate(bundle);
      final resolved = await store.resolve(
        'lifly.test.mint',
        requestedColorMode: ThemePackageColorMode.dark,
      );

      expect(installed.themeId, 'lifly.test.mint');
      expect(installed.version, '1.0.0');
      expect(await cache.readActiveVersion('lifly.test.mint'), '1.0.0');
      expect(resolved.snapshot.familyId, 'lifly.test.mint');
      expect(resolved.snapshot.packageVersion, '1.0.0');
      expect(resolved.degraded, isFalse);
    },
  );

  test('failed update keeps the previous known-good version active', () async {
    final cache = MemoryThemePackageCache();
    final store = _store(
      cache: cache,
      entitlements: LocalThemeEntitlementProvider(),
    );
    await store.installAndActivate(_signedBundle(version: '1.0.0'));
    final invalid = _signedBundle(version: '2.0.0');
    final invalidJson =
        jsonDecode(jsonEncode(invalid.packageJson)) as Map<String, dynamic>;
    final manifest = invalidJson['manifest'] as Map<String, dynamic>;
    final integrity = manifest['integrity'] as Map<String, dynamic>;
    integrity['digest'] = 'f' * 64;

    await expectLater(
      store.installAndActivate(ThemePackageBundle(packageJson: invalidJson)),
      throwsA(isA<ThemePackageIntegrityException>()),
    );

    expect(await cache.readActiveVersion('lifly.test.mint'), '1.0.0');
    final resolved = await store.resolve('lifly.test.mint');
    expect(resolved.snapshot.packageVersion, '1.0.0');
  });

  test(
    'corrupted active version rolls back to a prior cached version',
    () async {
      final cache = MemoryThemePackageCache();
      final store = _store(
        cache: cache,
        entitlements: LocalThemeEntitlementProvider(),
      );
      await store.installAndActivate(_signedBundle(version: '1.0.0'));
      await store.installAndActivate(_signedBundle(version: '2.0.0'));

      final corruptJson = _copyFixture();
      final corruptManifest = corruptJson['manifest'] as Map<String, dynamic>;
      corruptManifest['version'] = '2.0.0';
      await cache.writeVersion(ThemePackageBundle(packageJson: corruptJson));

      final resolved = await store.resolve('lifly.test.mint');

      expect(resolved.snapshot.packageVersion, '1.0.0');
      expect(resolved.degraded, isTrue);
      expect(await cache.readActiveVersion('lifly.test.mint'), '1.0.0');
    },
  );

  test(
    'cached paid theme can remain available with an offline grant',
    () async {
      final cache = MemoryThemePackageCache();
      final entitlements = LocalThemeEntitlementProvider();
      final store = _store(cache: cache, entitlements: entitlements);
      final bundle = _signedBundle(
        themeId: 'lifly.paid.focus',
        entitlementType: 'paid',
      );
      entitlements.setGrant(
        'lifly.paid.focus',
        ThemeEntitlementGrant.allowed(
          validUntil: DateTime.utc(2026, 8, 1),
          offlineAllowed: true,
        ),
      );

      await store.installAndActivate(bundle, now: DateTime.utc(2026, 7, 16));
      final resolved = await store.resolve(
        'lifly.paid.focus',
        offline: true,
        now: DateTime.utc(2026, 7, 20),
      );

      expect(resolved.snapshot.familyId, 'lifly.paid.focus');
      expect(resolved.degraded, isFalse);
    },
  );

  test(
    'default signature verifier rejects unconfigured official packages',
    () async {
      final cache = MemoryThemePackageCache();
      final store = ThemePackageStore(
        cache: cache,
        integrityVerifier: const ThemePackageIntegrityVerifier(),
        entitlementProvider: LocalThemeEntitlementProvider(),
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      );

      await expectLater(
        store.installAndActivate(_signedBundle()),
        throwsA(isA<ThemePackageIntegrityException>()),
      );
      expect(await cache.listVersions('lifly.test.mint'), isEmpty);
    },
  );

  test('missing required assets reject installation before caching', () async {
    final cache = MemoryThemePackageCache();
    final store = _store(
      cache: cache,
      entitlements: LocalThemeEntitlementProvider(),
    );
    final json = _copyFixture();
    final manifest = json['manifest'] as Map<String, dynamic>;
    final assets = manifest['assets'] as List<dynamic>;
    final asset = assets.single as Map<String, dynamic>;
    asset['required'] = true;
    _resign(json);

    await expectLater(
      store.installAndActivate(ThemePackageBundle(packageJson: json)),
      throwsA(isA<ThemePackageIntegrityException>()),
    );
    expect(await cache.listVersions('lifly.test.mint'), isEmpty);
  });

  test('incompatible cached package degrades to Lifly Core', () async {
    final cache = MemoryThemePackageCache();
    final store = _store(
      cache: cache,
      entitlements: LocalThemeEntitlementProvider(),
    );
    final json = _copyFixture();
    final manifest = json['manifest'] as Map<String, dynamic>;
    manifest['minimum_app_version'] = '9.0.0';
    _resign(json);
    final bundle = ThemePackageBundle(packageJson: json);
    await cache.writeVersion(bundle);
    await cache.activateVersion(bundle.themeId, bundle.version);

    final resolved = await store.resolve(bundle.themeId);

    expect(resolved.snapshot.familyId, LiflyCoreTheme.familyId);
    expect(resolved.degraded, isTrue);
  });

  test('denied entitlement follows declared fallback then Core', () async {
    final cache = MemoryThemePackageCache();
    final entitlements = LocalThemeEntitlementProvider();
    final store = _store(cache: cache, entitlements: entitlements);
    await store.installAndActivate(_signedBundle());

    final paid = _signedBundle(
      themeId: 'lifly.paid.focus',
      fallbackThemeId: 'lifly.test.mint',
      entitlementType: 'paid',
    );
    entitlements.setGrant(
      'lifly.paid.focus',
      ThemeEntitlementGrant.allowed(
        validUntil: DateTime.utc(2026, 8, 1),
        offlineAllowed: true,
      ),
    );
    await store.installAndActivate(paid, now: DateTime.utc(2026, 7, 16));
    entitlements.setGrant(
      'lifly.paid.focus',
      const ThemeEntitlementGrant.denied('subscription expired'),
    );

    final fallback = await store.resolve(
      'lifly.paid.focus',
      now: DateTime.utc(2026, 7, 17),
    );
    expect(fallback.snapshot.familyId, 'lifly.test.mint');
    expect(fallback.degraded, isTrue);

    await cache.clear();
    final core = await store.resolve('lifly.paid.focus');
    expect(core.snapshot.familyId, LiflyCoreTheme.familyId);
    expect(core.degraded, isTrue);
  });
}
