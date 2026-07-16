import 'dart:typed_data';

import 'package:client_flutter/app/theme/theme_package_bundle.dart';
import 'package:crypto/crypto.dart';

abstract interface class ThemeSignatureVerifier {
  Future<bool> verify({
    required String signer,
    required String signature,
    required String digest,
  });
}

class RejectingThemeSignatureVerifier implements ThemeSignatureVerifier {
  const RejectingThemeSignatureVerifier();

  @override
  Future<bool> verify({
    required String signer,
    required String signature,
    required String digest,
  }) async {
    return false;
  }
}

class LocalThemeSignatureVerifier implements ThemeSignatureVerifier {
  const LocalThemeSignatureVerifier();

  @override
  Future<bool> verify({
    required String signer,
    required String signature,
    required String digest,
  }) async {
    if (signer != 'lifly.official' && signer != 'lifly.builtin') {
      return false;
    }
    return signature == 'sig:$digest';
  }
}

class ThemePackageIntegrityVerifier {
  final ThemeSignatureVerifier signatureVerifier;

  const ThemePackageIntegrityVerifier({
    this.signatureVerifier = const RejectingThemeSignatureVerifier(),
  });

  Future<void> verify(ThemePackageBundle bundle) async {
    final package = bundle.package;
    final integrity = package.manifest.integrity;
    final digest = bundle.canonicalDigest;
    if (integrity.digest != digest) {
      throw ThemePackageIntegrityException(
        package.manifest.themeId,
        'package digest mismatch',
      );
    }

    final signatureValid = await signatureVerifier.verify(
      signer: integrity.signer,
      signature: integrity.signature,
      digest: digest,
    );
    if (!signatureValid) {
      throw ThemePackageIntegrityException(
        package.manifest.themeId,
        'package signature is invalid',
      );
    }

    final declarations = {
      for (final asset in package.manifest.assets) asset.path: asset,
    };
    for (final path in bundle.assetPaths) {
      if (!declarations.containsKey(path)) {
        throw ThemePackageIntegrityException(
          package.manifest.themeId,
          'undeclared asset: $path',
        );
      }
    }
    for (final declaration in package.manifest.assets) {
      final bytes = bundle.assetBytes(declaration.path);
      if (bytes == null) {
        if (declaration.required) {
          throw ThemePackageIntegrityException(
            package.manifest.themeId,
            'required asset is missing: ${declaration.path}',
          );
        }
        continue;
      }
      _verifyAsset(
        themeId: package.manifest.themeId,
        path: declaration.path,
        bytes: bytes,
        maximumBytes: declaration.maximumBytes,
        expectedDigest: declaration.sha256,
      );
    }
  }
}

void _verifyAsset({
  required String themeId,
  required String path,
  required Uint8List bytes,
  required int maximumBytes,
  required String expectedDigest,
}) {
  if (bytes.lengthInBytes > maximumBytes) {
    throw ThemePackageIntegrityException(
      themeId,
      'asset exceeds maximum size: $path',
    );
  }
  final digest = sha256.convert(bytes).toString();
  if (digest != expectedDigest) {
    throw ThemePackageIntegrityException(
      themeId,
      'asset digest mismatch: $path',
    );
  }
}

class ThemePackageIntegrityException implements Exception {
  final String themeId;
  final String message;

  const ThemePackageIntegrityException(this.themeId, this.message);

  @override
  String toString() => 'ThemePackageIntegrityException($themeId): $message';
}
