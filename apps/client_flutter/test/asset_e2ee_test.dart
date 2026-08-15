import 'dart:convert';

import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/features/asset/data/asset_e2ee_cipher.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final adk = AccountDataKey.fromBytes(
    keyVersion: 7,
    bytes: List<int>.generate(32, (index) => index + 1),
  );
  final wrongAdk = AccountDataKey.fromBytes(
    keyVersion: 7,
    bytes: List<int>.generate(32, (index) => 200 - index),
  );

  test(
    'asset bytes are chunk-encrypted and recover with wrapped asset key',
    () async {
      final cipher = AssetE2eeCipher(chunkSize: 16);
      final plaintext = utf8.encode(
        'Lifly attachment plaintext that must never enter object storage.',
      );

      final encrypted = await cipher.encrypt(
        assetId: 'asset-1',
        plaintext: plaintext,
        adk: adk,
      );

      expect(encrypted.chunkCount, greaterThan(1));
      expect(encrypted.wrappedAssetKey.adkKeyVersion, 7);
      expect(encrypted.wrappedAssetKey.encryptionVersion, 1);
      expect(encrypted.plaintextSizeBytes, plaintext.length);
      expect(encrypted.ciphertextSizeBytes, encrypted.ciphertext.length);
      expect(
        latin1.decode(encrypted.ciphertext, allowInvalid: true),
        isNot(contains('attachment plaintext')),
      );
      expect(encrypted.plaintextSha256, hasLength(64));
      expect(encrypted.ciphertextSha256, hasLength(64));

      final restored = await cipher.decrypt(
        assetId: 'asset-1',
        ciphertext: encrypted.ciphertext,
        wrappedAssetKey: encrypted.wrappedAssetKey,
        adk: adk,
      );

      expect(restored, plaintext);
    },
  );

  test('wrong ADK cannot unwrap an asset key', () async {
    final cipher = AssetE2eeCipher(chunkSize: 32);
    final encrypted = await cipher.encrypt(
      assetId: 'asset-2',
      plaintext: List<int>.generate(96, (index) => index),
      adk: adk,
    );

    expect(
      () => cipher.decrypt(
        assetId: 'asset-2',
        ciphertext: encrypted.ciphertext,
        wrappedAssetKey: encrypted.wrappedAssetKey,
        adk: wrongAdk,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('asset ciphertext tampering is authenticated per chunk', () async {
    final cipher = AssetE2eeCipher(chunkSize: 24);
    final encrypted = await cipher.encrypt(
      assetId: 'asset-3',
      plaintext: List<int>.generate(120, (index) => (index * 3) % 251),
      adk: adk,
    );
    final tampered = List<int>.from(encrypted.ciphertext);
    tampered[tampered.length - 20] ^= 0x01;

    expect(
      () => cipher.decrypt(
        assetId: 'asset-3',
        ciphertext: tampered,
        wrappedAssetKey: encrypted.wrappedAssetKey,
        adk: adk,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test(
    'asset key can be re-wrapped to a newer ADK without re-encrypting content',
    () async {
      final cipher = AssetE2eeCipher(chunkSize: 32);
      final nextAdk = AccountDataKey.fromBytes(
        keyVersion: 8,
        bytes: List<int>.generate(32, (index) => 100 + index),
      );
      final plaintext = List<int>.generate(80, (index) => index * 2);
      final encrypted = await cipher.encrypt(
        assetId: 'asset-rotate',
        plaintext: plaintext,
        adk: adk,
      );

      final rewrapped = await cipher.rewrapAssetKey(
        assetId: 'asset-rotate',
        wrappedAssetKey: encrypted.wrappedAssetKey,
        oldAdk: adk,
        newAdk: nextAdk,
      );

      expect(rewrapped.adkKeyVersion, 8);
      expect(rewrapped.ciphertext, isNot(encrypted.wrappedAssetKey.ciphertext));
      expect(
        await cipher.decrypt(
          assetId: 'asset-rotate',
          ciphertext: encrypted.ciphertext,
          wrappedAssetKey: rewrapped,
          adk: nextAdk,
        ),
        plaintext,
      );
    },
  );

  test('wrapped asset key is bound to asset id', () async {
    final cipher = AssetE2eeCipher(chunkSize: 32);
    final encrypted = await cipher.encrypt(
      assetId: 'asset-4',
      plaintext: const [1, 2, 3, 4],
      adk: adk,
    );

    expect(
      () => cipher.decrypt(
        assetId: 'asset-other',
        ciphertext: encrypted.ciphertext,
        wrappedAssetKey: encrypted.wrappedAssetKey,
        adk: adk,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
