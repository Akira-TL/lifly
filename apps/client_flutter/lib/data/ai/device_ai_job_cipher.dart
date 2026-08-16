import 'dart:convert';

import 'package:client_flutter/data/ai/ai_job_envelope.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
import 'package:cryptography/cryptography.dart';

class DeviceAiJobCipher {
  static const int encryptionVersion = 1;
  static const int _macLength = 16;
  static const String _keyDomain = 'lifly/device-ai-job/key/v1';
  static const String _aadDomain = 'lifly/device-ai-job/aad/v1';

  final DeviceIdentityStore _identityStore;
  final Hkdf _kdf;
  final AesGcm _cipher;
  final List<int> Function()? _nonceFactory;

  DeviceAiJobCipher(
    this._identityStore, {
    Hkdf? kdf,
    AesGcm? cipher,
    List<int> Function()? nonce,
  }) : _kdf = kdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
       _cipher = cipher ?? AesGcm.with256bits(),
       _nonceFactory = nonce;

  Future<AiJobEnvelope> encryptJson({
    required String accountId,
    required String sourceDeviceId,
    required String targetDeviceId,
    required AiJobMessageType messageType,
    String? correlationId,
    required String jobId,
    required String idempotencyKey,
    required DateTime expiresAt,
    required String remotePublicKey,
    required Map<String, Object?> payload,
  }) async {
    final identity = await _identityStore.loadOrCreate();
    if (identity.deviceId != sourceDeviceId) {
      throw StateError(
        'Device identity ${identity.deviceId} cannot encrypt as $sourceDeviceId',
      );
    }
    final normalizedExpiry = _canonicalUtcMilliseconds(expiresAt);
    final context = _context(
      accountId: accountId,
      sourceDeviceId: sourceDeviceId,
      targetDeviceId: targetDeviceId,
      messageType: messageType,
      correlationId: correlationId,
      jobId: jobId,
      idempotencyKey: idempotencyKey,
      expiresAt: normalizedExpiry,
    );
    final secretKey = await _deriveKey(
      remotePublicKey: remotePublicKey,
      context: context,
    );
    final nonce = List<int>.from(_nonceFactory?.call() ?? _cipher.newNonce());
    if (nonce.length != 12) {
      throw const FormatException('Device AI job nonce must be 12 bytes');
    }
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: secretKey,
      nonce: nonce,
      aad: _aad(context),
    );
    return AiJobEnvelope(
      jobId: jobId,
      accountId: accountId,
      sourceDeviceId: sourceDeviceId,
      targetDeviceId: targetDeviceId,
      messageType: messageType,
      correlationId: correlationId,
      idempotencyKey: idempotencyKey,
      expiresAt: normalizedExpiry,
      encryptionVersion: encryptionVersion,
      nonce: _encodeBase64Url(nonce),
      ciphertext: _encodeBase64Url([...box.cipherText, ...box.mac.bytes]),
    );
  }

  Future<Map<String, dynamic>> decryptJson(
    AiJobEnvelope envelope, {
    required String remotePublicKey,
  }) async {
    if (envelope.encryptionVersion != encryptionVersion) {
      throw UnsupportedError(
        'Unsupported device AI job encryption version: '
        '${envelope.encryptionVersion}',
      );
    }
    final identity = await _identityStore.loadOrCreate();
    if (identity.deviceId != envelope.targetDeviceId) {
      throw StateError(
        'Device identity ${identity.deviceId} cannot decrypt job for '
        '${envelope.targetDeviceId}',
      );
    }
    final context = _context(
      accountId: envelope.accountId,
      sourceDeviceId: envelope.sourceDeviceId,
      targetDeviceId: envelope.targetDeviceId,
      messageType: envelope.messageType,
      correlationId: envelope.correlationId,
      jobId: envelope.jobId,
      idempotencyKey: envelope.idempotencyKey,
      expiresAt: envelope.expiresAt.toUtc(),
    );
    final secretKey = await _deriveKey(
      remotePublicKey: remotePublicKey,
      context: context,
    );
    final sealed = _decodeBase64Url(envelope.ciphertext);
    if (sealed.length <= _macLength) {
      throw const FormatException('Device AI job ciphertext is truncated');
    }
    final splitAt = sealed.length - _macLength;
    final clear = await _cipher.decrypt(
      SecretBox(
        sealed.sublist(0, splitAt),
        nonce: _decodeBase64Url(envelope.nonce),
        mac: Mac(sealed.sublist(splitAt)),
      ),
      secretKey: secretKey,
      aad: _aad(context),
    );
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map) {
      throw const FormatException('Device AI job plaintext must be an object');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<SecretKey> _deriveKey({
    required String remotePublicKey,
    required List<Object?> context,
  }) async {
    final shared = await _identityStore.deriveSharedSecret(
      remotePublicKey: remotePublicKey,
    );
    return _kdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('$_keyDomain/${context[1]}'),
      info: utf8.encode(jsonEncode(context)),
    );
  }

  List<Object?> _context({
    required String accountId,
    required String sourceDeviceId,
    required String targetDeviceId,
    required AiJobMessageType messageType,
    required String? correlationId,
    required String jobId,
    required String idempotencyKey,
    required DateTime expiresAt,
  }) => <Object?>[
    _keyDomain,
    accountId,
    sourceDeviceId,
    targetDeviceId,
    messageType.value,
    correlationId,
    jobId,
    idempotencyKey,
    _canonicalUtcMilliseconds(expiresAt).toIso8601String(),
    liflyAiJobProtocolVersion,
    encryptionVersion,
  ];

  List<int> _aad(List<Object?> context) =>
      utf8.encode(jsonEncode(<Object?>[_aadDomain, ...context.skip(1)]));
}

String _encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceFirst(RegExp(r'=+$'), '');

DateTime _canonicalUtcMilliseconds(DateTime value) =>
    DateTime.fromMillisecondsSinceEpoch(
      value.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );

List<int> _decodeBase64Url(String value) {
  final padding = (4 - value.length % 4) % 4;
  final suffix = List<String>.filled(padding, '=').join();
  return base64Url.decode('$value$suffix');
}
