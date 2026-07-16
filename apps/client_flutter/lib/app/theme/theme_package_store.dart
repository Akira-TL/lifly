import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_color_mode.dart';
import 'package:client_flutter/app/theme/theme_entitlement.dart';
import 'package:client_flutter/app/theme/theme_integrity.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_bundle.dart';
import 'package:client_flutter/app/theme/theme_package_cache.dart';
import 'package:client_flutter/app/theme/theme_package_resolver.dart';
import 'package:client_flutter/app/theme/theme_snapshot.dart';
import 'package:flutter/foundation.dart';

@immutable
class InstalledThemePackageVersion {
  final String themeId;
  final String version;

  const InstalledThemePackageVersion({
    required this.themeId,
    required this.version,
  });
}

@immutable
class ThemePackageResolution {
  final ThemeSnapshot snapshot;
  final bool degraded;
  final List<String> diagnostics;

  const ThemePackageResolution({
    required this.snapshot,
    required this.degraded,
    required this.diagnostics,
  });
}

class ThemePackageStore {
  final ThemePackageCache cache;
  final ThemePackageIntegrityVerifier integrityVerifier;
  final ThemeEntitlementProvider entitlementProvider;
  final String appVersion;
  final ThemeTargetPlatform platform;

  const ThemePackageStore({
    required this.cache,
    required this.integrityVerifier,
    required this.entitlementProvider,
    required this.appVersion,
    required this.platform,
  });

  Future<InstalledThemePackageVersion> installAndActivate(
    ThemePackageBundle bundle, {
    bool offline = false,
    DateTime? now,
  }) async {
    final checkedAt = (now ?? DateTime.now()).toUtc();
    await integrityVerifier.verify(bundle);
    final package = bundle.package;
    await ThemePackageResolver(
      package: package,
      appVersion: appVersion,
      platform: platform,
    ).resolve();
    await _requireEntitlement(
      package.manifest,
      offline: offline,
      now: checkedAt,
    );

    await cache.writeVersion(bundle);
    await cache.activateVersion(bundle.themeId, bundle.version);
    return InstalledThemePackageVersion(
      themeId: bundle.themeId,
      version: bundle.version,
    );
  }

  Future<ThemePackageResolution> resolve(
    String themeId, {
    ThemePackageColorMode requestedColorMode = ThemePackageColorMode.system,
    bool offline = false,
    DateTime? now,
  }) async {
    return _resolve(
      themeId,
      requestedColorMode: requestedColorMode,
      offline: offline,
      now: (now ?? DateTime.now()).toUtc(),
      visited: <String>{},
      diagnostics: <String>[],
      degraded: false,
    );
  }

  Future<ThemePackageResolution> _resolve(
    String themeId, {
    required ThemePackageColorMode requestedColorMode,
    required bool offline,
    required DateTime now,
    required Set<String> visited,
    required List<String> diagnostics,
    required bool degraded,
  }) async {
    if (themeId == LiflyCoreTheme.familyId || !visited.add(themeId)) {
      if (themeId != LiflyCoreTheme.familyId) {
        diagnostics.add('Fallback cycle detected for $themeId');
      }
      return ThemePackageResolution(
        snapshot: _coreSnapshot(requestedColorMode, platform),
        degraded: degraded || themeId != LiflyCoreTheme.familyId,
        diagnostics: List.unmodifiable(diagnostics),
      );
    }

    final activeVersion = await cache.readActiveVersion(themeId);
    final versions = await cache.listVersions(themeId);
    final candidates = _orderedVersions(activeVersion, versions);
    String? declaredFallback;

    for (final version in candidates) {
      try {
        final bundle = await cache.readVersion(themeId, version);
        if (bundle == null) {
          diagnostics.add('Missing cached bundle $themeId@$version');
          continue;
        }
        await integrityVerifier.verify(bundle);
        final package = bundle.package;
        declaredFallback ??= package.manifest.fallbackThemeId;
        await _requireEntitlement(package.manifest, offline: offline, now: now);
        final snapshot = await ThemePackageResolver(
          package: package,
          appVersion: appVersion,
          platform: platform,
          requestedColorMode: requestedColorMode,
        ).resolve();
        if (version != activeVersion) {
          await cache.activateVersion(themeId, version);
          diagnostics.add('Rolled back $themeId to $version');
        }
        return ThemePackageResolution(
          snapshot: snapshot,
          degraded: degraded || version != activeVersion,
          diagnostics: List.unmodifiable(diagnostics),
        );
      } catch (error) {
        diagnostics.add('Rejected $themeId@$version: $error');
      }
    }

    final fallback = declaredFallback;
    if (fallback != null && fallback != themeId) {
      diagnostics.add('Falling back from $themeId to $fallback');
      return _resolve(
        fallback,
        requestedColorMode: requestedColorMode,
        offline: offline,
        now: now,
        visited: visited,
        diagnostics: diagnostics,
        degraded: true,
      );
    }

    diagnostics.add('Falling back from $themeId to Lifly Core');
    return ThemePackageResolution(
      snapshot: _coreSnapshot(requestedColorMode, platform),
      degraded: true,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  Future<void> _requireEntitlement(
    ThemeManifest manifest, {
    required bool offline,
    required DateTime now,
  }) async {
    final grant = await entitlementProvider.resolve(
      manifest,
      offline: offline,
      now: now,
    );
    if (!grant.isUsable(offline: offline, now: now)) {
      throw ThemeEntitlementException(
        manifest.themeId,
        grant.reason ?? 'theme entitlement is not usable',
      );
    }
  }
}

ThemeSnapshot _coreSnapshot(
  ThemePackageColorMode requestedColorMode,
  ThemeTargetPlatform platform,
) {
  final resolved = resolveThemeColorMode(requestedColorMode, const {
    ThemePackageColorMode.system,
    ThemePackageColorMode.light,
    ThemePackageColorMode.dark,
  });
  return LiflyCoreTheme.snapshotFor(
    platform,
  ).copyWith(colorMode: resolved, themeMode: materialThemeMode(resolved));
}

List<String> _orderedVersions(String? active, Iterable<String> versions) {
  final remaining = versions.where((version) => version != active).toList()
    ..sort(_compareVersionsDescending);
  return [?active, ...remaining];
}

int _compareVersionsDescending(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  for (var index = 0; index < 3; index++) {
    final comparison = rightParts[index].compareTo(leftParts[index]);
    if (comparison != 0) return comparison;
  }
  return right.compareTo(left);
}

List<int> _versionParts(String version) {
  final parts = version.split('-').first.split('.');
  if (parts.length != 3) return const [0, 0, 0];
  return parts.map((part) => int.tryParse(part) ?? 0).toList(growable: false);
}
