import 'dart:convert';
import 'dart:typed_data';

import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

const int liflyAssetEncryptionVersion = 1;
const int liflyAssetKeyWrapVersion = 1;

class WrappedAssetKey {
  final int adkKeyVersion;
  final int encryptionVersion;
  final String nonce;
  final String ciphertext;

  const WrappedAssetKey({
    required this.adkKeyVersion,
    required this.encryptionVersion,
    required this.nonce,
    required this.ciphertext,
  });

  Map<String, Object?> toJson() => {
    'adk_key_version': adkKeyVersion,
    'encryption_version': encryptionVersion,
    'nonce': nonce,
    'ciphertext': ciphertext,
  };

  factory WrappedAssetKey.fromJson(Map<String, Object?> json) {
    return WrappedAssetKey(
      adkKeyVersion: _positiveInt(json['adk_key_version'], 'adk_key_version'),
      encryptionVersion: _positiveInt(
        json['encryption_version'],
        'encryption_version',
      ),
      nonce: _requiredString(json['nonce'], 'nonce'),
      ciphertext: _requiredString(json['ciphertext'], 'ciphertext'),
    );
  }
}

class EncryptedAssetPayload {
  final List<int> ciphertext;
  final WrappedAssetKey wrappedAssetKey;
  final int plaintextSizeBytes;
  final int ciphertextSizeBytes;
  final int chunkCount;
  final String plaintextSha256;
  final String ciphertextSha256;

  const EncryptedAssetPayload({
    required this.ciphertext,
    required this.wrappedAssetKey,
    required this.plaintextSizeBytes,
    required this.ciphertextSizeBytes,
    required this.chunkCount,
    required this.plaintextSha256,
    required this.ciphertextSha256,
  });
}

class AssetE2eeCipher {
  static final List<int> _magic = ascii.encode('LFLYAS01');
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _headerLength = 8 + 4 + 4 + 8;
  static const String _contentAadDomain = 'lifly/asset-content/v1';
  static const String _wrapAadDomain = 'lifly/asset-key-wrap/v1';

  final int chunkSize;
  final AesGcm _cipher;

  AssetE2eeCipher({this.chunkSize = 256 * 1024, AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits() {
    if (chunkSize < 1) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be positive');
    }
  }

  static bool hasEncryptedAssetMagic(List<int> bytes) {
    if (bytes.length < _magic.length) return false;
    for (var index = 0; index < _magic.length; index += 1) {
      if (bytes[index] != _magic[index]) return false;
    }
    return true;
  }

  Future<EncryptedAssetPayload> encrypt({
    required String assetId,
    required List<int> plaintext,
    required AccountDataKey adk,
  }) async {
    if (assetId.trim().isEmpty) {
      throw ArgumentError.value(assetId, 'assetId', 'must not be empty');
    }
    if (plaintext.isEmpty) {
      throw ArgumentError.value(plaintext, 'plaintext', 'must not be empty');
    }

    final assetSecretKey = await _cipher.newSecretKey();
    final wrappedAssetKey = await _wrapAssetKey(
      assetId: assetId,
      assetSecretKey: assetSecretKey,
      adk: adk,
    );
    final chunkCount = (plaintext.length + chunkSize - 1) ~/ chunkSize;
    final builder = BytesBuilder(copy: false);
    builder.add(_magic);
    builder.add(_uint32(chunkSize));
    builder.add(_uint32(chunkCount));
    builder.add(_uint64(plaintext.length));

    for (var index = 0; index < chunkCount; index += 1) {
      final start = index * chunkSize;
      final end = (start + chunkSize < plaintext.length)
          ? start + chunkSize
          : plaintext.length;
      final chunk = plaintext.sublist(start, end);
      final nonce = _cipher.newNonce();
      final box = await _cipher.encrypt(
        chunk,
        secretKey: assetSecretKey,
        nonce: nonce,
        aad: _contentAad(
          assetId: assetId,
          chunkIndex: index,
          plaintextLength: chunk.length,
        ),
      );
      final sealed = <int>[...box.cipherText, ...box.mac.bytes];
      builder
        ..add(nonce)
        ..add(_uint32(sealed.length))
        ..add(sealed);
    }

    final ciphertext = builder.takeBytes();
    return EncryptedAssetPayload(
      ciphertext: ciphertext,
      wrappedAssetKey: wrappedAssetKey,
      plaintextSizeBytes: plaintext.length,
      ciphertextSizeBytes: ciphertext.length,
      chunkCount: chunkCount,
      plaintextSha256: sha256.convert(plaintext).toString(),
      ciphertextSha256: sha256.convert(ciphertext).toString(),
    );
  }

  Future<List<int>> decrypt({
    required String assetId,
    required List<int> ciphertext,
    required WrappedAssetKey wrappedAssetKey,
    required AccountDataKey adk,
  }) async {
    if (!hasEncryptedAssetMagic(ciphertext) ||
        ciphertext.length < _headerLength) {
      throw const FormatException('Invalid Lifly encrypted asset header');
    }
    if (wrappedAssetKey.encryptionVersion != liflyAssetKeyWrapVersion) {
      throw UnsupportedError(
        'Unsupported asset key wrap version: ${wrappedAssetKey.encryptionVersion}',
      );
    }
    if (wrappedAssetKey.adkKeyVersion != adk.keyVersion) {
      throw StateError(
        'ADK version ${adk.keyVersion} cannot unwrap asset key version '
        '${wrappedAssetKey.adkKeyVersion}',
      );
    }

    final reader = _AssetByteReader(ciphertext, offset: _magic.length);
    final encodedChunkSize = reader.readUint32();
    final chunkCount = reader.readUint32();
    final plaintextLength = reader.readUint64();
    if (encodedChunkSize < 1 || chunkCount < 1 || plaintextLength < 1) {
      throw const FormatException('Invalid encrypted asset dimensions');
    }

    final assetSecretKey = await _unwrapAssetKey(
      assetId: assetId,
      wrappedAssetKey: wrappedAssetKey,
      adk: adk,
    );
    final clearBuilder = BytesBuilder(copy: false);
    for (var index = 0; index < chunkCount; index += 1) {
      final nonce = reader.readBytes(_nonceLength);
      final sealedLength = reader.readUint32();
      if (sealedLength <= _macLength) {
        throw const FormatException('Encrypted asset chunk is truncated');
      }
      final sealed = reader.readBytes(sealedLength);
      final splitAt = sealed.length - _macLength;
      final expectedPlaintextLength = index == chunkCount - 1
          ? plaintextLength - (encodedChunkSize * (chunkCount - 1))
          : encodedChunkSize;
      if (expectedPlaintextLength < 1 ||
          expectedPlaintextLength > encodedChunkSize) {
        throw const FormatException('Invalid encrypted asset chunk length');
      }
      final box = SecretBox(
        sealed.sublist(0, splitAt),
        nonce: nonce,
        mac: Mac(sealed.sublist(splitAt)),
      );
      final chunk = await _cipher.decrypt(
        box,
        secretKey: assetSecretKey,
        aad: _contentAad(
          assetId: assetId,
          chunkIndex: index,
          plaintextLength: expectedPlaintextLength,
        ),
      );
      if (chunk.length != expectedPlaintextLength) {
        throw const FormatException(
          'Encrypted asset plaintext length mismatch',
        );
      }
      clearBuilder.add(chunk);
    }
    if (!reader.isAtEnd) {
      throw const FormatException('Encrypted asset contains trailing bytes');
    }
    final plaintext = clearBuilder.takeBytes();
    if (plaintext.length != plaintextLength) {
      throw const FormatException('Encrypted asset total length mismatch');
    }
    return plaintext;
  }

  Future<WrappedAssetKey> _wrapAssetKey({
    required String assetId,
    required SecretKey assetSecretKey,
    required AccountDataKey adk,
  }) async {
    final nonce = _cipher.newNonce();
    final assetKeyBytes = await assetSecretKey.extractBytes();
    final box = await _cipher.encrypt(
      assetKeyBytes,
      secretKey: adk.secretKey,
      nonce: nonce,
      aad: _wrapAad(
        assetId: assetId,
        adkKeyVersion: adk.keyVersion,
        encryptionVersion: liflyAssetKeyWrapVersion,
      ),
    );
    return WrappedAssetKey(
      adkKeyVersion: adk.keyVersion,
      encryptionVersion: liflyAssetKeyWrapVersion,
      nonce: base64Url.encode(nonce),
      ciphertext: base64Url.encode([...box.cipherText, ...box.mac.bytes]),
    );
  }

  Future<SecretKey> _unwrapAssetKey({
    required String assetId,
    required WrappedAssetKey wrappedAssetKey,
    required AccountDataKey adk,
  }) async {
    final nonce = base64Url.decode(wrappedAssetKey.nonce);
    final sealed = base64Url.decode(wrappedAssetKey.ciphertext);
    if (sealed.length <= _macLength) {
      throw const FormatException('Wrapped asset key is truncated');
    }
    final splitAt = sealed.length - _macLength;
    final clear = await _cipher.decrypt(
      SecretBox(
        sealed.sublist(0, splitAt),
        nonce: nonce,
        mac: Mac(sealed.sublist(splitAt)),
      ),
      secretKey: adk.secretKey,
      aad: _wrapAad(
        assetId: assetId,
        adkKeyVersion: wrappedAssetKey.adkKeyVersion,
        encryptionVersion: wrappedAssetKey.encryptionVersion,
      ),
    );
    if (clear.length != AccountDataKey.byteLength) {
      throw const FormatException(
        'Unwrapped Asset Data Key has invalid length',
      );
    }
    return SecretKey(clear);
  }

  List<int> _contentAad({
    required String assetId,
    required int chunkIndex,
    required int plaintextLength,
  }) {
    return utf8.encode(
      jsonEncode({
        'domain': _contentAadDomain,
        'asset_id': assetId,
        'encryption_version': liflyAssetEncryptionVersion,
        'chunk_index': chunkIndex,
        'plaintext_length': plaintextLength,
      }),
    );
  }

  List<int> _wrapAad({
    required String assetId,
    required int adkKeyVersion,
    required int encryptionVersion,
  }) {
    return utf8.encode(
      jsonEncode({
        'domain': _wrapAadDomain,
        'asset_id': assetId,
        'adk_key_version': adkKeyVersion,
        'encryption_version': encryptionVersion,
      }),
    );
  }
}

class _AssetByteReader {
  final List<int> bytes;
  int offset;

  _AssetByteReader(this.bytes, {required this.offset});

  bool get isAtEnd => offset == bytes.length;

  int readUint32() {
    final value = _readNumber(4, (data) => data.getUint32(0, Endian.big));
    return value;
  }

  int readUint64() {
    final value = _readNumber(8, (data) => data.getUint64(0, Endian.big));
    return value;
  }

  List<int> readBytes(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('Encrypted asset payload is truncated');
    }
    final result = bytes.sublist(offset, offset + length);
    offset += length;
    return result;
  }

  int _readNumber(int length, int Function(ByteData data) read) {
    final valueBytes = readBytes(length);
    return read(ByteData.sublistView(Uint8List.fromList(valueBytes)));
  }
}

List<int> _uint32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

List<int> _uint64(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _positiveInt(Object? value, String field) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  throw FormatException('$field must be a positive integer');
}

String _requiredString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$field must be a non-empty string');
}
