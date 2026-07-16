import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_color_mode.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_resolver.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_snapshot.dart';
import 'package:flutter/foundation.dart';

@immutable
class InstalledThemeFamily {
  final String familyId;
  final String displayName;
  final Set<ThemePackageColorMode> supportedColorModes;
  final ThemePerformanceClass performanceClass;
  final bool isCore;

  const InstalledThemeFamily({
    required this.familyId,
    required this.displayName,
    required this.supportedColorModes,
    required this.performanceClass,
    required this.isCore,
  });
}

class ThemeRegistry {
  static const coreColorModes = <ThemePackageColorMode>{
    ThemePackageColorMode.system,
    ThemePackageColorMode.light,
    ThemePackageColorMode.dark,
  };

  final Map<String, ThemePackage> _packages;

  ThemeRegistry({Iterable<ThemePackage> packages = const []})
    : _packages = {
        for (final package in packages) package.manifest.themeId: package,
      } {
    if (_packages.containsKey(LiflyCoreTheme.familyId)) {
      throw const ThemeRegistryException(
        'Lifly Core is built in and cannot be replaced by a package',
      );
    }
  }

  List<InstalledThemeFamily> get installedThemes {
    final themes = <InstalledThemeFamily>[
      const InstalledThemeFamily(
        familyId: LiflyCoreTheme.familyId,
        displayName: 'Lifly Core',
        supportedColorModes: coreColorModes,
        performanceClass: ThemePerformanceClass.core,
        isCore: true,
      ),
      ..._packages.values.map(
        (package) => InstalledThemeFamily(
          familyId: package.manifest.themeId,
          displayName: package.manifest.displayName,
          supportedColorModes: package.manifest.supportedColorModes,
          performanceClass: package.manifest.performanceClass,
          isCore: false,
        ),
      ),
    ];
    themes.sort((left, right) {
      if (left.isCore) return -1;
      if (right.isCore) return 1;
      return left.displayName.compareTo(right.displayName);
    });
    return List.unmodifiable(themes);
  }

  bool contains(String familyId) {
    return familyId == LiflyCoreTheme.familyId ||
        _packages.containsKey(familyId);
  }

  Set<ThemePackageColorMode> supportedColorModes(String familyId) {
    if (familyId == LiflyCoreTheme.familyId) return coreColorModes;
    final package = _packages[familyId];
    if (package == null) {
      throw ThemeRegistryException('Theme family is not installed: $familyId');
    }
    return package.manifest.supportedColorModes;
  }

  Future<ThemeSnapshot> resolve({
    required ThemePreference preference,
    required String appVersion,
    required ThemeTargetPlatform platform,
  }) async {
    if (preference.familyId == LiflyCoreTheme.familyId) {
      final resolved = resolveThemeColorMode(
        preference.colorMode,
        coreColorModes,
      );
      return LiflyCoreTheme.snapshot.copyWith(
        colorMode: resolved,
        themeMode: materialThemeMode(resolved),
      );
    }

    final package = _packages[preference.familyId];
    if (package == null) {
      throw ThemeRegistryException(
        'Theme family is not installed: ${preference.familyId}',
      );
    }
    return ThemePackageResolver(
      package: package,
      appVersion: appVersion,
      platform: platform,
      requestedColorMode: preference.colorMode,
    ).resolve();
  }
}

class ThemeRegistryException implements Exception {
  final String message;

  const ThemeRegistryException(this.message);

  @override
  String toString() => 'ThemeRegistryException: $message';
}
