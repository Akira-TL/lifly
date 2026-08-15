import 'dart:convert';

import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/crypto/encrypted_payload_cipher.dart';
import 'package:client_flutter/data/crypto/password_key_envelope_cipher.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const userId = 'account-1';
  const entityId = 'memo-1';
  final updatedAt = DateTime.utc(2026, 8, 15, 10);
  final dataKey = AccountDataKey.fromBytes(
    keyVersion: 3,
    bytes: List<int>.generate(32, (index) => index + 1),
  );
  final wrongDataKey = AccountDataKey.fromBytes(
    keyVersion: 3,
    bytes: List<int>.generate(32, (index) => 255 - index),
  );
  final cipher = EncryptedPayloadCipher();

  test('encrypted entity round-trips through AES-256-GCM envelope', () async {
    final envelope = await cipher.encryptEntity(
      key: dataKey,
      id: entityId,
      userId: userId,
      entityType: 'memo',
      revision: 7,
      lifecycleStatus: EncryptedEntityLifecycleStatus.active,
      updatedAt: updatedAt,
      payload: {
        'title': '只应存在于密文内',
        'content_markdown': 'private body',
        'tags': ['private'],
      },
    );

    final payload = await cipher.decryptEntity(envelope, key: dataKey);

    expect(payload['title'], '只应存在于密文内');
    expect(payload['content_markdown'], 'private body');
    expect(payload['tags'], ['private']);
    expect(envelope.keyVersion, 3);
    expect(envelope.encryptionVersion, 1);
    expect(envelope.nonce, isNotEmpty);
    expect(envelope.ciphertext, isNot(contains('private body')));
  });

  test('wrong ADK cannot decrypt encrypted entity', () async {
    final envelope = await cipher.encryptEntity(
      key: dataKey,
      id: entityId,
      userId: userId,
      entityType: 'memo',
      revision: 1,
      lifecycleStatus: EncryptedEntityLifecycleStatus.active,
      updatedAt: updatedAt,
      payload: const {'title': 'secret'},
    );

    await expectLater(
      cipher.decryptEntity(envelope, key: wrongDataKey),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('AAD detects metadata tampering', () async {
    final envelope = await cipher.encryptEntity(
      key: dataKey,
      id: entityId,
      userId: userId,
      entityType: 'memo',
      revision: 4,
      lifecycleStatus: EncryptedEntityLifecycleStatus.active,
      updatedAt: updatedAt,
      payload: const {'title': 'secret'},
    );
    final tampered = EncryptedEntityEnvelope(
      id: envelope.id,
      userId: envelope.userId,
      entityType: envelope.entityType,
      revision: 5,
      lifecycleStatus: envelope.lifecycleStatus,
      updatedAt: envelope.updatedAt,
      keyVersion: envelope.keyVersion,
      encryptionVersion: envelope.encryptionVersion,
      nonce: envelope.nonce,
      ciphertext: envelope.ciphertext,
    );

    await expectLater(
      cipher.decryptEntity(tampered, key: dataKey),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('ciphertext tampering is rejected', () async {
    final envelope = await cipher.encryptEntity(
      key: dataKey,
      id: entityId,
      userId: userId,
      entityType: 'memo',
      revision: 1,
      lifecycleStatus: EncryptedEntityLifecycleStatus.active,
      updatedAt: updatedAt,
      payload: const {'title': 'secret'},
    );
    final encoded = base64Url.decode(envelope.ciphertext);
    encoded[0] ^= 0x01;
    final tampered = EncryptedEntityEnvelope(
      id: envelope.id,
      userId: envelope.userId,
      entityType: envelope.entityType,
      revision: envelope.revision,
      lifecycleStatus: envelope.lifecycleStatus,
      updatedAt: envelope.updatedAt,
      keyVersion: envelope.keyVersion,
      encryptionVersion: envelope.encryptionVersion,
      nonce: envelope.nonce,
      ciphertext: base64Url.encode(encoded),
    );

    await expectLater(
      cipher.decryptEntity(tampered, key: dataKey),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test(
    'unsupported encryption version is rejected before decryption',
    () async {
      final envelope = EncryptedEntityEnvelope(
        id: entityId,
        userId: userId,
        entityType: 'memo',
        revision: 1,
        lifecycleStatus: EncryptedEntityLifecycleStatus.active,
        updatedAt: updatedAt,
        keyVersion: dataKey.keyVersion,
        encryptionVersion: 99,
        nonce: base64Url.encode(List<int>.filled(12, 1)),
        ciphertext: base64Url.encode(List<int>.filled(32, 2)),
      );

      await expectLater(
        cipher.decryptEntity(envelope, key: dataKey),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test('Password Key Envelope wraps ADK from client-only export key', () async {
    final wrapper = PasswordKeyEnvelopeCipher();
    final clientExportKey = SecretKey(
      utf8.encode('opaque-client-export-key-material-for-demo'),
    );

    final envelope = await wrapper.wrap(
      accountId: userId,
      dataKey: dataKey,
      clientExportKey: clientExportKey,
    );
    final unwrapped = await wrapper.unwrap(
      envelope,
      clientExportKey: clientExportKey,
    );

    expect(await unwrapped.extractBytes(), await dataKey.extractBytes());
    expect(unwrapped.keyVersion, dataKey.keyVersion);
    expect(envelope.accountId, userId);
    expect(envelope.ciphertext, isNotEmpty);
  });

  test('wrong client-only export key cannot unwrap ADK', () async {
    final wrapper = PasswordKeyEnvelopeCipher();
    final correct = SecretKey(List<int>.generate(32, (index) => index + 7));
    final wrong = SecretKey(List<int>.generate(32, (index) => index + 17));
    final envelope = await wrapper.wrap(
      accountId: userId,
      dataKey: dataKey,
      clientExportKey: correct,
    );

    await expectLater(
      wrapper.unwrap(envelope, clientExportKey: wrong),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
