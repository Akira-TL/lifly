import 'package:client_flutter/app/theme/theme_entitlement.dart';
import 'package:client_flutter/app/theme/theme_integrity.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_cache.dart';
import 'package:client_flutter/app/theme/theme_package_store.dart';
import 'package:flutter/foundation.dart';

@immutable
class ThemeCacheBootstrapResult {
  final List<ThemePackage> packages;
  final List<String> diagnostics;

  const ThemeCacheBootstrapResult({
    required this.packages,
    required this.diagnostics,
  });
}

class ThemeCacheBootstrapper {
  final ThemePackageCache cache;
  final ThemePackageIntegrityVerifier integrityVerifier;
  final ThemeEntitlementProvider entitlementProvider;
  final String appVersion;
  final ThemeTargetPlatform platform;

  const ThemeCacheBootstrapper({
    required this.cache,
    required this.integrityVerifier,
    required this.entitlementProvider,
    required this.appVersion,
    required this.platform,
  });

  Future<ThemeCacheBootstrapResult> load({
    bool offline = false,
    DateTime? now,
  }) async {
    final store = ThemePackageStore(
      cache: cache,
      integrityVerifier: integrityVerifier,
      entitlementProvider: entitlementProvider,
      appVersion: appVersion,
      platform: platform,
    );
    final packages = <ThemePackage>[];
    final diagnostics = <String>[];
    for (final themeId in await cache.listThemeIds()) {
      try {
        final resolution = await store.resolve(
          themeId,
          offline: offline,
          now: now,
        );
        diagnostics.addAll(resolution.diagnostics);
        if (resolution.snapshot.familyId != themeId) continue;
        final activeVersion = await cache.readActiveVersion(themeId);
        if (activeVersion == null) continue;
        final bundle = await cache.readVersion(themeId, activeVersion);
        if (bundle == null) continue;
        packages.add(bundle.package);
      } catch (error) {
        diagnostics.add('Skipped cached theme $themeId: $error');
      }
    }
    return ThemeCacheBootstrapResult(
      packages: List.unmodifiable(packages),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }
}
