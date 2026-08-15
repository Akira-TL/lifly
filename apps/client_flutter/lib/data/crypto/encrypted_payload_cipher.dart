import 'dart:convert';

import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:cryptography/cryptography.dart';

class EncryptedPayloadCipher {
  static const int encryptionVersion = 1;
  static const int _gcmMacLength = 16;
  static const String _aadDomain = 'lifly/encrypted-entity/v1';

  final AesGcm _cipher;

  EncryptedPayloadCipher({AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  Future<EncryptedEntityEnvelope> encryptEntity({
    required AccountDataKey key,
    required String id,
    required String userId,
    required String entityType,
    required int revision,
    required EncryptedEntityLifecycleStatus lifecycleStatus,
    required DateTime updatedAt,
    required Map<String, Object?> payload,
  }) async {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
    final normalizedUpdatedAt = updatedAt.toUtc();
    final nonce = _cipher.newNonce();
    final aad = _entityAad(
      id: id,
      userId: userId,
      entityType: entityType,
      revision: revision,
      lifecycleStatus: lifecycleStatus,
      updatedAt: normalizedUpdatedAt,
      keyVersion: key.keyVersion,
      encryptionVersion: encryptionVersion,
    );
    final clearText = utf8.encode(jsonEncode(payload));
    final box = await _cipher.encrypt(
      clearText,
      secretKey: key.secretKey,
      nonce: nonce,
      aad: aad,
    );
    final sealed = <int>[...box.cipherText, ...box.mac.bytes];

    return EncryptedEntityEnvelope(
      id: id,
      userId: userId,
      entityType: entityType,
      revision: revision,
      lifecycleStatus: lifecycleStatus,
      updatedAt: normalizedUpdatedAt,
      keyVersion: key.keyVersion,
      encryptionVersion: encryptionVersion,
      nonce: base64Url.encode(nonce),
      ciphertext: base64Url.encode(sealed),
    );
  }

  Future<Map<String, Object?>> decryptEntity(
    EncryptedEntityEnvelope envelope, {
    required AccountDataKey key,
  }) async {
    if (envelope.encryptionVersion != encryptionVersion) {
      throw UnsupportedError(
        'Unsupported encrypted entity version: ${envelope.encryptionVersion}',
      );
    }
    if (envelope.keyVersion != key.keyVersion) {
      throw StateError(
        'ADK version ${key.keyVersion} cannot decrypt envelope key version '
        '${envelope.keyVersion}',
      );
    }

    final nonce = base64Url.decode(envelope.nonce);
    final sealed = base64Url.decode(envelope.ciphertext);
    if (sealed.length <= _gcmMacLength) {
      throw const FormatException('Encrypted entity ciphertext is truncated');
    }
    final splitAt = sealed.length - _gcmMacLength;
    final box = SecretBox(
      sealed.sublist(0, splitAt),
      nonce: nonce,
      mac: Mac(sealed.sublist(splitAt)),
    );
    final clearText = await _cipher.decrypt(
      box,
      secretKey: key.secretKey,
      aad: _entityAad(
        id: envelope.id,
        userId: envelope.userId,
        entityType: envelope.entityType,
        revision: envelope.revision,
        lifecycleStatus: envelope.lifecycleStatus,
        updatedAt: envelope.updatedAt.toUtc(),
        keyVersion: envelope.keyVersion,
        encryptionVersion: envelope.encryptionVersion,
      ),
    );
    final decoded = jsonDecode(utf8.decode(clearText));
    if (decoded is! Map) {
      throw const FormatException('Encrypted entity payload must be an object');
    }
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
  }

  List<int> _entityAad({
    required String id,
    required String userId,
    required String entityType,
    required int revision,
    required EncryptedEntityLifecycleStatus lifecycleStatus,
    required DateTime updatedAt,
    required int keyVersion,
    required int encryptionVersion,
  }) {
    return utf8.encode(
      jsonEncode({
        'domain': _aadDomain,
        'id': id,
        'user_id': userId,
        'entity_type': entityType,
        'revision': revision,
        'lifecycle_status': lifecycleStatus.value,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'key_version': keyVersion,
        'encryption_version': encryptionVersion,
      }),
    );
  }
}
