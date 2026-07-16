import 'package:client_flutter/app/theme/theme_tokens.dart';
import 'package:flutter/foundation.dart';

enum ThemeTargetPlatform { web, phone, desktop }

enum ThemePackageColorMode { system, light, dark, oled, highContrast }

enum ThemePerformanceClass { core, standard, rich }

enum ThemeEntitlementType { builtin, free, paid, subscription, promotional }

enum ThemeAssetKind { image, font, icon, animation }

@immutable
class ThemePackage {
  final ThemeManifest manifest;
  final ThemeTokenSet tokens;

  const ThemePackage({required this.manifest, required this.tokens});

  factory ThemePackage.fromJson(Map<String, dynamic> json) {
    _rejectExecutableContent(json);
    _rejectUnknownKeys(json, const {'manifest', 'tokens'}, 'theme package');
    return ThemePackage(
      manifest: ThemeManifest.fromJson(_requiredMap(json, 'manifest')),
      tokens: ThemeTokenSet.fromJson(_requiredMap(json, 'tokens')),
    );
  }
}

@immutable
class ThemeManifest {
  final String themeId;
  final String version;
  final String displayName;
  final String description;
  final String author;
  final String minimumAppVersion;
  final Set<ThemeTargetPlatform> supportedPlatforms;
  final Set<ThemePackageColorMode> supportedColorModes;
  final ThemePerformanceClass performanceClass;
  final List<ThemeAssetDeclaration> assets;
  final String fallbackThemeId;
  final ThemeEntitlementType entitlementType;
  final ThemeIntegrityMetadata integrity;

  const ThemeManifest({
    required this.themeId,
    required this.version,
    required this.displayName,
    required this.description,
    required this.author,
    required this.minimumAppVersion,
    required this.supportedPlatforms,
    required this.supportedColorModes,
    required this.performanceClass,
    required this.assets,
    required this.fallbackThemeId,
    required this.entitlementType,
    required this.integrity,
  });

  factory ThemeManifest.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {
      'theme_id',
      'version',
      'display_name',
      'description',
      'author',
      'minimum_app_version',
      'supported_platforms',
      'supported_color_modes',
      'performance_class',
      'assets',
      'fallback_theme_id',
      'entitlement_type',
      'integrity',
    }, 'theme manifest');

    final themeId = _requiredString(json, 'theme_id');
    if (!RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)+$').hasMatch(themeId)) {
      throw const ThemePackageFormatException(
        'theme_id must be a stable lowercase namespaced identifier',
      );
    }

    final version = _requiredString(json, 'version');
    final minimumAppVersion = _requiredString(json, 'minimum_app_version');
    _validateSemanticVersion(version, 'version');
    _validateSemanticVersion(minimumAppVersion, 'minimum_app_version');

    final supportedPlatforms = _enumSet(
      json,
      'supported_platforms',
      _platformByName,
    );
    final supportedColorModes = _enumSet(
      json,
      'supported_color_modes',
      _colorModeByName,
    );
    if (supportedColorModes.isEmpty) {
      throw const ThemePackageFormatException(
        'supported_color_modes cannot be empty',
      );
    }

    final assetsJson = json['assets'];
    if (assetsJson is! List) {
      throw const ThemePackageFormatException('assets must be a list');
    }
    final assets = assetsJson
        .map((item) {
          if (item is! Map) {
            throw const ThemePackageFormatException(
              'each asset must be an object',
            );
          }
          return ThemeAssetDeclaration.fromJson(item.cast<String, dynamic>());
        })
        .toList(growable: false);
    final assetIds = assets.map((item) => item.id).toSet();
    if (assetIds.length != assets.length) {
      throw const ThemePackageFormatException('asset ids must be unique');
    }

    return ThemeManifest(
      themeId: themeId,
      version: version,
      displayName: _requiredString(json, 'display_name'),
      description: _requiredString(json, 'description'),
      author: _requiredString(json, 'author'),
      minimumAppVersion: minimumAppVersion,
      supportedPlatforms: supportedPlatforms,
      supportedColorModes: supportedColorModes,
      performanceClass: _requiredEnum(
        json,
        'performance_class',
        _performanceClassByName,
      ),
      assets: assets,
      fallbackThemeId: _requiredString(json, 'fallback_theme_id'),
      entitlementType: _requiredEnum(
        json,
        'entitlement_type',
        _entitlementTypeByName,
      ),
      integrity: ThemeIntegrityMetadata.fromJson(
        _requiredMap(json, 'integrity'),
      ),
    );
  }
}

@immutable
class ThemeAssetDeclaration {
  final String id;
  final String path;
  final ThemeAssetKind kind;
  final bool required;
  final int maximumBytes;
  final String sha256;

  const ThemeAssetDeclaration({
    required this.id,
    required this.path,
    required this.kind,
    required this.required,
    required this.maximumBytes,
    required this.sha256,
  });

  factory ThemeAssetDeclaration.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {
      'id',
      'path',
      'kind',
      'required',
      'maximum_bytes',
      'sha256',
    }, 'theme asset');

    final path = _requiredString(json, 'path');
    if (!_isSafeRelativeAssetPath(path)) {
      throw ThemePackageFormatException('unsafe asset path: $path');
    }

    final required = json['required'];
    if (required is! bool) {
      throw const ThemePackageFormatException('asset.required must be a bool');
    }
    final maximumBytes = json['maximum_bytes'];
    if (maximumBytes is! int ||
        maximumBytes <= 0 ||
        maximumBytes > 50 * 1024 * 1024) {
      throw const ThemePackageFormatException(
        'asset.maximum_bytes must be between 1 and 52428800',
      );
    }
    final sha256 = _requiredString(json, 'sha256');
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw const ThemePackageFormatException(
        'asset.sha256 must be a 64-character hex digest',
      );
    }

    return ThemeAssetDeclaration(
      id: _requiredString(json, 'id'),
      path: path,
      kind: _requiredEnum(json, 'kind', _assetKindByName),
      required: required,
      maximumBytes: maximumBytes,
      sha256: sha256.toLowerCase(),
    );
  }
}

@immutable
class ThemeIntegrityMetadata {
  final String algorithm;
  final String digest;
  final String signer;
  final String signature;

  const ThemeIntegrityMetadata({
    required this.algorithm,
    required this.digest,
    required this.signer,
    required this.signature,
  });

  factory ThemeIntegrityMetadata.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {
      'algorithm',
      'digest',
      'signer',
      'signature',
    }, 'theme integrity');
    final algorithm = _requiredString(json, 'algorithm');
    if (algorithm != 'sha256') {
      throw const ThemePackageFormatException(
        'only sha256 package integrity is supported',
      );
    }
    final digest = _requiredString(json, 'digest');
    if (!_sha256Pattern.hasMatch(digest)) {
      throw const ThemePackageFormatException(
        'integrity.digest must be a 64-character hex digest',
      );
    }
    final signer = _requiredString(json, 'signer');
    if (signer != 'lifly.official' && signer != 'lifly.builtin') {
      throw const ThemePackageFormatException(
        'v0.8.0 accepts only Lifly trusted theme signers',
      );
    }
    return ThemeIntegrityMetadata(
      algorithm: algorithm,
      digest: digest.toLowerCase(),
      signer: signer,
      signature: _requiredString(json, 'signature'),
    );
  }
}

class ThemePackageFormatException implements Exception {
  final String message;

  const ThemePackageFormatException(this.message);

  @override
  String toString() => 'ThemePackageFormatException: $message';
}

const _platformByName = {
  'web': ThemeTargetPlatform.web,
  'phone': ThemeTargetPlatform.phone,
  'desktop': ThemeTargetPlatform.desktop,
};

const _colorModeByName = {
  'system': ThemePackageColorMode.system,
  'light': ThemePackageColorMode.light,
  'dark': ThemePackageColorMode.dark,
  'oled': ThemePackageColorMode.oled,
  'high_contrast': ThemePackageColorMode.highContrast,
};

const _performanceClassByName = {
  'core': ThemePerformanceClass.core,
  'standard': ThemePerformanceClass.standard,
  'rich': ThemePerformanceClass.rich,
};

const _entitlementTypeByName = {
  'builtin': ThemeEntitlementType.builtin,
  'free': ThemeEntitlementType.free,
  'paid': ThemeEntitlementType.paid,
  'subscription': ThemeEntitlementType.subscription,
  'promotional': ThemeEntitlementType.promotional,
};

const _assetKindByName = {
  'image': ThemeAssetKind.image,
  'font': ThemeAssetKind.font,
  'icon': ThemeAssetKind.icon,
  'animation': ThemeAssetKind.animation,
};

final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');
const _prohibitedExecutableFields = {
  'script',
  'scripts',
  'code',
  'dart',
  'dart_entrypoint',
  'entry_point',
  'executable',
  'expression',
  'api_path',
  'database_query',
};

void _rejectExecutableContent(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (_prohibitedExecutableFields.contains(key)) {
        throw ThemePackageFormatException(
          'theme packages cannot contain executable field: $key',
        );
      }
      _rejectExecutableContent(entry.value);
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _rejectExecutableContent(item);
    }
  }
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw ThemePackageFormatException('$key must be an object');
  }
  return value.cast<String, dynamic>();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw ThemePackageFormatException('$key must be a non-empty string');
  }
  return value.trim();
}

Set<T> _enumSet<T>(
  Map<String, dynamic> json,
  String key,
  Map<String, T> values,
) {
  final raw = json[key];
  if (raw is! List || raw.isEmpty) {
    throw ThemePackageFormatException('$key must be a non-empty list');
  }
  final result = <T>{};
  for (final item in raw) {
    if (item is! String || values[item] == null) {
      throw ThemePackageFormatException(
        '$key contains unsupported value: $item',
      );
    }
    result.add(values[item] as T);
  }
  return result;
}

T _requiredEnum<T>(
  Map<String, dynamic> json,
  String key,
  Map<String, T> values,
) {
  final raw = json[key];
  if (raw is! String || values[raw] == null) {
    throw ThemePackageFormatException('$key contains unsupported value: $raw');
  }
  return values[raw] as T;
}

void _rejectUnknownKeys(
  Map<String, dynamic> json,
  Set<String> allowed,
  String context,
) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw ThemePackageFormatException(
      '$context contains unsupported fields: ${unknown.join(', ')}',
    );
  }
}

void _validateSemanticVersion(String value, String field) {
  if (!RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$').hasMatch(value)) {
    throw ThemePackageFormatException('$field must use semantic versioning');
  }
}

bool _isSafeRelativeAssetPath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.startsWith('\\')) {
    return false;
  }
  if (path.contains('\\') || path.contains(':') || path.contains('\u0000')) {
    return false;
  }
  final segments = path.split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}
