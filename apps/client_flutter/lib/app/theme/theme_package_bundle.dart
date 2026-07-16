import 'dart:convert';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

@immutable
class ThemePackageBundle {
  final Map<String, dynamic> _packageJson;
  final Map<String, Uint8List> _assets;

  ThemePackageBundle({
    required Map<String, dynamic> packageJson,
    Map<String, Uint8List> assets = const {},
  }) : _packageJson = _deepCopyMap(packageJson),
       _assets = {
         for (final entry in assets.entries)
           entry.key: Uint8List.fromList(entry.value),
       };

  Map<String, dynamic> get packageJson => _deepCopyMap(_packageJson);

  Map<String, Uint8List> get assets => Map.unmodifiable({
    for (final entry in _assets.entries)
      entry.key: Uint8List.fromList(entry.value),
  });

  ThemePackage get package => ThemePackage.fromJson(_packageJson);

  String get themeId => package.manifest.themeId;

  String get version => package.manifest.version;

  String get canonicalDigest => computeCanonicalDigest(_packageJson);

  Uint8List? assetBytes(String path) {
    final bytes = _assets[path];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  Iterable<String> get assetPaths => List.unmodifiable(_assets.keys);

  Map<String, dynamic> toCacheJson() {
    return {
      'package': _deepCopyMap(_packageJson),
      'assets': {
        for (final entry in _assets.entries)
          entry.key: base64Encode(entry.value),
      },
    };
  }

  factory ThemePackageBundle.fromCacheJson(Map<String, dynamic> json) {
    final packageValue = json['package'];
    final assetsValue = json['assets'];
    if (packageValue is! Map || assetsValue is! Map) {
      throw const ThemePackageBundleException('Invalid cached theme bundle');
    }
    final assets = <String, Uint8List>{};
    for (final entry in assetsValue.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const ThemePackageBundleException(
          'Invalid cached theme asset entry',
        );
      }
      try {
        assets[entry.key as String] = base64Decode(entry.value as String);
      } on FormatException catch (error) {
        throw ThemePackageBundleException(
          'Invalid cached theme asset encoding: $error',
        );
      }
    }
    return ThemePackageBundle(
      packageJson: packageValue.cast<String, dynamic>(),
      assets: assets,
    );
  }

  static String computeCanonicalDigest(Map<String, dynamic> packageJson) {
    final payload = _deepCopyMap(packageJson);
    final manifest = payload['manifest'];
    if (manifest is Map) {
      final integrity = manifest['integrity'];
      if (integrity is Map) {
        integrity.remove('digest');
        integrity.remove('signature');
      }
    }
    final canonical = jsonEncode(_canonicalize(payload));
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

class ThemePackageBundleException implements Exception {
  final String message;

  const ThemePackageBundleException(this.message);

  @override
  String toString() => 'ThemePackageBundleException: $message';
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
  return (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}
