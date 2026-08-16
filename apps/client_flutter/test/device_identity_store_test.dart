import 'dart:convert';

import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test(
    'device identity is stable and private key stays in secret store',
    () async {
      final secrets = _MemorySecrets();
      var sequence = 0;
      final store = SecureDeviceIdentityStore(
        secrets,
        newDeviceId: () => 'device-${++sequence}',
        algorithm: X25519(),
      );

      final first = await store.loadOrCreate();
      final second = await store.loadOrCreate();

      expect(first.deviceId, 'device-1');
      expect(second.deviceId, first.deviceId);
      expect(second.publicKey, first.publicKey);
      expect(sequence, 1);
      expect(secrets.values['lifly.device.id.v1'], 'device-1');
      expect(secrets.values['lifly.device.x25519.private.v1'], isNotNull);
      expect(
        secrets.values.values,
        isNot(contains(first.publicKey)),
        reason:
            'public key is derived; only private seed and stable id are stored',
      );

      final remoteKeyPair = await X25519().newKeyPair();
      final remotePublic = await remoteKeyPair.extractPublicKey();
      final localShared = await store.deriveSharedSecret(
        remotePublicKey: base64Encode(remotePublic.bytes),
      );
      final remoteShared = await X25519().sharedSecretKey(
        keyPair: remoteKeyPair,
        remotePublicKey: SimplePublicKey(
          base64Decode(first.publicKey),
          type: KeyPairType.x25519,
        ),
      );
      expect(
        await localShared.extractBytes(),
        await remoteShared.extractBytes(),
      );
    },
  );

  test(
    'clear removes device id and private key so the next account gets a new identity',
    () async {
      final secrets = _MemorySecrets();
      var sequence = 0;
      final store = SecureDeviceIdentityStore(
        secrets,
        newDeviceId: () => 'device-${++sequence}',
        algorithm: X25519(),
      );

      final first = await store.loadOrCreate();
      await store.clear();
      expect(secrets.values['lifly.device.id.v1'], isNull);
      expect(secrets.values['lifly.device.x25519.private.v1'], isNull);

      final second = await store.loadOrCreate();
      expect(second.deviceId, 'device-2');
      expect(second.deviceId, isNot(first.deviceId));
      expect(second.publicKey, isNot(first.publicKey));
    },
  );

  test(
    'malformed private key is rejected instead of regenerated silently',
    () async {
      final secrets = _MemorySecrets();
      await secrets.write('lifly.device.id.v1', 'device-1');
      await secrets.write('lifly.device.x25519.private.v1', 'not-base64%%%');
      final store = SecureDeviceIdentityStore(
        secrets,
        newDeviceId: () => 'should-not-run',
        algorithm: X25519(),
      );

      expect(store.loadOrCreate(), throwsA(isA<DeviceIdentityCorrupt>()));
    },
  );
}
