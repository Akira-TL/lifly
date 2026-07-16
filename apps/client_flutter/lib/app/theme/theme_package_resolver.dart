import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:flutter/material.dart';

class ThemePackageResolver implements ThemeResolver {
  final ThemePackage package;
  final String appVersion;
  final ThemeTargetPlatform platform;

  const ThemePackageResolver({
    required this.package,
    required this.appVersion,
    required this.platform,
  });

  @override
  Future<ThemeSnapshot> resolve() async {
    final manifest = package.manifest;
    if (!_isVersionAtLeast(appVersion, manifest.minimumAppVersion)) {
      throw ThemePackageCompatibilityException(
        'Theme ${manifest.themeId} requires app ${manifest.minimumAppVersion} or newer',
      );
    }
    if (!manifest.supportedPlatforms.contains(platform)) {
      throw ThemePackageCompatibilityException(
        'Theme ${manifest.themeId} does not support ${platform.name}',
      );
    }

    return ThemeSnapshot(
      familyId: manifest.themeId,
      displayName: manifest.displayName,
      packageVersion: manifest.version,
      performanceClass: manifest.performanceClass,
      tokens: package.tokens,
      lightTheme: package.tokens.buildTheme(Brightness.light),
      darkTheme: package.tokens.buildTheme(Brightness.dark),
      themeMode: _defaultThemeMode(manifest.supportedColorModes),
    );
  }
}

class ThemePackageCompatibilityException implements Exception {
  final String message;

  const ThemePackageCompatibilityException(this.message);

  @override
  String toString() => 'ThemePackageCompatibilityException: $message';
}

ThemeMode _defaultThemeMode(Set<ThemePackageColorMode> modes) {
  if (modes.contains(ThemePackageColorMode.system) ||
      modes.containsAll({
        ThemePackageColorMode.light,
        ThemePackageColorMode.dark,
      })) {
    return ThemeMode.system;
  }
  if (modes.contains(ThemePackageColorMode.dark) ||
      modes.contains(ThemePackageColorMode.oled)) {
    return ThemeMode.dark;
  }
  return ThemeMode.light;
}

bool _isVersionAtLeast(String current, String minimum) {
  final currentParts = _stableVersionParts(current);
  final minimumParts = _stableVersionParts(minimum);
  for (var index = 0; index < 3; index++) {
    if (currentParts[index] > minimumParts[index]) return true;
    if (currentParts[index] < minimumParts[index]) return false;
  }
  return true;
}

List<int> _stableVersionParts(String value) {
  final stable = value.split('-').first;
  final parts = stable.split('.');
  if (parts.length != 3) {
    throw ThemePackageCompatibilityException(
      'Invalid semantic version: $value',
    );
  }
  return parts
      .map((part) {
        final parsed = int.tryParse(part);
        if (parsed == null) {
          throw ThemePackageCompatibilityException(
            'Invalid semantic version: $value',
          );
        }
        return parsed;
      })
      .toList(growable: false);
}
