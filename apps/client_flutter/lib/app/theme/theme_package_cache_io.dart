import 'dart:convert';
import 'dart:io';

import 'package:client_flutter/app/theme/theme_package_bundle.dart';
import 'package:client_flutter/app/theme/theme_package_cache.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileThemePackageCache implements ThemePackageCache {
  final Directory rootDirectory;

  FileThemePackageCache(this.rootDirectory);

  @override
  Future<void> writeVersion(ThemePackageBundle bundle) async {
    final directory = _versionDirectory(bundle.themeId, bundle.version);
    await directory.create(recursive: true);
    await _writeJsonAtomically(
      File(p.join(directory.path, 'bundle.json')),
      bundle.toCacheJson(),
    );
  }

  @override
  Future<ThemePackageBundle?> readVersion(
    String themeId,
    String version,
  ) async {
    final target = File(
      p.join(_versionDirectory(themeId, version).path, 'bundle.json'),
    );
    final file = await _recoverTarget(target);
    if (file == null) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('cached bundle is not an object');
      }
      return ThemePackageBundle.fromCacheJson(decoded.cast<String, dynamic>());
    } on Object catch (error) {
      throw ThemePackageCacheException(
        'Cannot decode cached theme $themeId@$version: $error',
      );
    }
  }

  @override
  Future<List<String>> listThemeIds() async {
    if (!await rootDirectory.exists()) return const [];
    final themeIds = <String>[];
    await for (final entity in rootDirectory.list(followLinks: false)) {
      if (entity is Directory) themeIds.add(p.basename(entity.path));
    }
    themeIds.sort();
    return List.unmodifiable(themeIds);
  }

  @override
  Future<List<String>> listVersions(String themeId) async {
    final directory = Directory(
      p.join(_themeDirectory(themeId).path, 'versions'),
    );
    if (!await directory.exists()) return const [];
    final versions = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) versions.add(p.basename(entity.path));
    }
    versions.sort();
    return List.unmodifiable(versions);
  }

  @override
  Future<String?> readActiveVersion(String themeId) async {
    final target = File(p.join(_themeDirectory(themeId).path, 'active'));
    final file = await _recoverTarget(target);
    if (file == null) return null;
    final version = (await file.readAsString()).trim();
    return version.isEmpty ? null : version;
  }

  @override
  Future<void> activateVersion(String themeId, String version) async {
    final bundle = await readVersion(themeId, version);
    if (bundle == null) {
      throw ThemePackageCacheException(
        'Cannot activate missing theme version: $themeId@$version',
      );
    }
    final themeDirectory = _themeDirectory(themeId);
    await themeDirectory.create(recursive: true);
    await _writeTextAtomically(
      File(p.join(themeDirectory.path, 'active')),
      version,
    );
  }

  @override
  Future<void> clear() async {
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  }

  Directory _themeDirectory(String themeId) {
    _validatePathSegment(themeId, 'theme id');
    return Directory(p.join(rootDirectory.path, themeId));
  }

  Directory _versionDirectory(String themeId, String version) {
    _validatePathSegment(version, 'theme version');
    return Directory(
      p.join(_themeDirectory(themeId).path, 'versions', version),
    );
  }
}

Future<void> _writeJsonAtomically(File target, Map<String, dynamic> value) {
  return _writeTextAtomically(target, jsonEncode(value));
}

Future<void> _writeTextAtomically(File target, String value) async {
  await target.parent.create(recursive: true);
  await _recoverTarget(target);
  final temporary = File('${target.path}.tmp');
  final backup = File('${target.path}.bak');
  if (await temporary.exists()) await temporary.delete();
  await temporary.writeAsString(value, flush: true);
  if (await backup.exists()) await backup.delete();
  if (await target.exists()) await target.rename(backup.path);
  try {
    await temporary.rename(target.path);
    if (await backup.exists()) await backup.delete();
  } catch (_) {
    if (await target.exists()) await target.delete();
    if (await backup.exists()) await backup.rename(target.path);
    rethrow;
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<File?> _recoverTarget(File target) async {
  if (await target.exists()) return target;
  final backup = File('${target.path}.bak');
  if (!await backup.exists()) return null;
  await target.parent.create(recursive: true);
  await backup.rename(target.path);
  return target;
}

void _validatePathSegment(String value, String label) {
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value) ||
      value == '.' ||
      value == '..') {
    throw ThemePackageCacheException('Invalid $label: $value');
  }
}

Future<ThemePackageCache> createDefaultThemePackageCache() async {
  final supportDirectory = await getApplicationSupportDirectory();
  return FileThemePackageCache(
    Directory(p.join(supportDirectory.path, 'lifly', 'theme-packages')),
  );
}
