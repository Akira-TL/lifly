import 'package:client_flutter/app/theme/theme_package_bundle.dart';

abstract interface class ThemePackageCache {
  Future<void> writeVersion(ThemePackageBundle bundle);

  Future<ThemePackageBundle?> readVersion(String themeId, String version);

  Future<List<String>> listVersions(String themeId);

  Future<String?> readActiveVersion(String themeId);

  Future<void> activateVersion(String themeId, String version);

  Future<void> clear();
}

class MemoryThemePackageCache implements ThemePackageCache {
  final Map<String, Map<String, ThemePackageBundle>> _versions = {};
  final Map<String, String> _activeVersions = {};

  @override
  Future<void> writeVersion(ThemePackageBundle bundle) async {
    _versions.putIfAbsent(bundle.themeId, () => {})[bundle.version] = bundle;
  }

  @override
  Future<ThemePackageBundle?> readVersion(
    String themeId,
    String version,
  ) async {
    return _versions[themeId]?[version];
  }

  @override
  Future<List<String>> listVersions(String themeId) async {
    return List.unmodifiable(_versions[themeId]?.keys ?? const <String>[]);
  }

  @override
  Future<String?> readActiveVersion(String themeId) async {
    return _activeVersions[themeId];
  }

  @override
  Future<void> activateVersion(String themeId, String version) async {
    if (_versions[themeId]?[version] == null) {
      throw ThemePackageCacheException(
        'Cannot activate missing theme version: $themeId@$version',
      );
    }
    _activeVersions[themeId] = version;
  }

  @override
  Future<void> clear() async {
    _versions.clear();
    _activeVersions.clear();
  }
}

class ThemePackageCacheException implements Exception {
  final String message;

  const ThemePackageCacheException(this.message);

  @override
  String toString() => 'ThemePackageCacheException: $message';
}
