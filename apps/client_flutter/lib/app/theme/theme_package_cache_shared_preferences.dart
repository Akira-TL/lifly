import 'dart:convert';

import 'package:client_flutter/app/theme/theme_package_bundle.dart';
import 'package:client_flutter/app/theme/theme_package_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cachePrefix = 'lifly.theme_cache';

class SharedPreferencesThemePackageCache implements ThemePackageCache {
  static const _themeIdsKey = '$_cachePrefix.theme_ids';

  final SharedPreferencesAsync _preferences;

  SharedPreferencesThemePackageCache({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  @override
  Future<void> writeVersion(ThemePackageBundle bundle) async {
    final themeIds = await _readStringSet(_themeIdsKey)
      ..add(bundle.themeId);
    final versionsKey = _versionsKey(bundle.themeId);
    final versions = await _readStringSet(versionsKey)
      ..add(bundle.version);
    await Future.wait<void>([
      _preferences.setString(
        _themeIdsKey,
        jsonEncode(themeIds.toList()..sort()),
      ),
      _preferences.setString(
        versionsKey,
        jsonEncode(versions.toList()..sort()),
      ),
      _preferences.setString(
        _bundleKey(bundle.themeId, bundle.version),
        jsonEncode(bundle.toCacheJson()),
      ),
    ]);
  }

  @override
  Future<ThemePackageBundle?> readVersion(
    String themeId,
    String version,
  ) async {
    final encoded = await _preferences.getString(_bundleKey(themeId, version));
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('cached bundle is not an object');
      }
      return ThemePackageBundle.fromCacheJson(decoded.cast<String, dynamic>());
    } on FormatException catch (error) {
      throw ThemePackageCacheException(
        'Cannot decode cached theme $themeId@$version: $error',
      );
    }
  }

  @override
  Future<List<String>> listVersions(String themeId) async {
    final versions = await _readStringSet(_versionsKey(themeId));
    return List.unmodifiable(versions);
  }

  @override
  Future<String?> readActiveVersion(String themeId) {
    return _preferences.getString(_activeKey(themeId));
  }

  @override
  Future<void> activateVersion(String themeId, String version) async {
    final versions = await _readStringSet(_versionsKey(themeId));
    if (!versions.contains(version)) {
      throw ThemePackageCacheException(
        'Cannot activate missing theme version: $themeId@$version',
      );
    }
    await _preferences.setString(_activeKey(themeId), version);
  }

  @override
  Future<void> clear() async {
    final themeIds = await _readStringSet(_themeIdsKey);
    for (final themeId in themeIds) {
      final versions = await _readStringSet(_versionsKey(themeId));
      for (final version in versions) {
        await _preferences.remove(_bundleKey(themeId, version));
      }
      await _preferences.remove(_versionsKey(themeId));
      await _preferences.remove(_activeKey(themeId));
    }
    await _preferences.remove(_themeIdsKey);
  }

  Future<Set<String>> _readStringSet(String key) async {
    final encoded = await _preferences.getString(key);
    if (encoded == null) return <String>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List || decoded.any((value) => value is! String)) {
        throw const FormatException('value is not a string list');
      }
      return decoded.cast<String>().toSet();
    } on FormatException catch (error) {
      throw ThemePackageCacheException(
        'Cannot decode cache index $key: $error',
      );
    }
  }
}

String _versionsKey(String themeId) {
  _validateCacheIdentifier(themeId, 'theme id');
  return '$_cachePrefix.$themeId.versions';
}

String _activeKey(String themeId) {
  _validateCacheIdentifier(themeId, 'theme id');
  return '$_cachePrefix.$themeId.active';
}

String _bundleKey(String themeId, String version) {
  _validateCacheIdentifier(themeId, 'theme id');
  _validateCacheIdentifier(version, 'theme version');
  return '$_cachePrefix.$themeId.bundle.$version';
}

void _validateCacheIdentifier(String value, String label) {
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value) ||
      value == '.' ||
      value == '..') {
    throw ThemePackageCacheException('Invalid $label: $value');
  }
}

Future<ThemePackageCache> createDefaultThemePackageCache() async {
  return SharedPreferencesThemePackageCache();
}
