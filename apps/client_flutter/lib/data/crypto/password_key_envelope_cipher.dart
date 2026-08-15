import 'dart:convert';

import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:cryptography/cryptography.dart';

class PasswordKeyEnvelopeCipher {
  static const int encryptionVersion = 1;
  static const int _gcmMacLength = 16;
  static const String _kdfDomain = 'lifly/adk-wrapping-key/v1';
  static const String _aadDomain = 'lifly/password-key-envelope/v1';

  final AesGcm _cipher;
  final Hkdf _hkdf;

  PasswordKeyEnvelopeCipher({AesGcm? cipher, Hkdf? hkdf})
    : _cipher = cipher ?? AesGcm.with256bits(),
      _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Future<PasswordKeyEnvelope> wrap({
    required String accountId,
    required AccountDataKey dataKey,
    required SecretKey clientExportKey,
  }) async {
    final wrappingKey = await _deriveWrappingKey(
      accountId: accountId,
      keyVersion: dataKey.keyVersion,
      clientExportKey: clientExportKey,
    );
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      await dataKey.extractBytes(),
      secretKey: wrappingKey,
      nonce: nonce,
      aad: _aad(accountId: accountId, keyVersion: dataKey.keyVersion),
    );
    final sealed = <int>[...box.cipherText, ...box.mac.bytes];
    return PasswordKeyEnvelope(
      accountId: accountId,
      keyVersion: dataKey.keyVersion,
      encryptionVersion: encryptionVersion,
      nonce: base64Url.encode(nonce),
      ciphertext: base64Url.encode(sealed),
    );
  }

  Future<AccountDataKey> unwrap(
    PasswordKeyEnvelope envelope, {
    required SecretKey clientExportKey,
  }) async {
    if (envelope.encryptionVersion != encryptionVersion) {
      throw UnsupportedError(
        'Unsupported password key envelope version: '
        '${envelope.encryptionVersion}',
      );
    }
    final sealed = base64Url.decode(envelope.ciphertext);
    if (sealed.length <= _gcmMacLength) {
      throw const FormatException(
        'Password key envelope ciphertext is truncated',
      );
    }
    final splitAt = sealed.length - _gcmMacLength;
    final wrappingKey = await _deriveWrappingKey(
      accountId: envelope.accountId,
      keyVersion: envelope.keyVersion,
      clientExportKey: clientExportKey,
    );
    final clearText = await _cipher.decrypt(
      SecretBox(
        sealed.sublist(0, splitAt),
        nonce: base64Url.decode(envelope.nonce),
        mac: Mac(sealed.sublist(splitAt)),
      ),
      secretKey: wrappingKey,
      aad: _aad(accountId: envelope.accountId, keyVersion: envelope.keyVersion),
    );
    return AccountDataKey.fromBytes(
      keyVersion: envelope.keyVersion,
      bytes: clearText,
    );
  }

  Future<SecretKey> _deriveWrappingKey({
    required String accountId,
    required int keyVersion,
    required SecretKey clientExportKey,
  }) {
    return _hkdf.deriveKey(
      secretKey: clientExportKey,
      nonce: utf8.encode('$_kdfDomain/account/$accountId'),
      info: utf8.encode('$_kdfDomain/key-version/$keyVersion'),
    );
  }

  List<int> _aad({required String accountId, required int keyVersion}) {
    return utf8.encode(
      jsonEncode({
        'domain': _aadDomain,
        'account_id': accountId,
        'key_version': keyVersion,
        'encryption_version': encryptionVersion,
      }),
    );
  }
}
