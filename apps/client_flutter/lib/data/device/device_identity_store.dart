import 'dart:convert';

import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  final String deviceId;
  final String publicKey;
  final int keyVersion;

  const DeviceIdentity({
    required this.deviceId,
    required this.publicKey,
    required this.keyVersion,
  });
}

class DeviceIdentityCorrupt implements Exception {
  final String message;

  const DeviceIdentityCorrupt(this.message);

  @override
  String toString() => 'DeviceIdentityCorrupt: $message';
}

abstract interface class DeviceIdentityStore {
  Future<DeviceIdentity> loadOrCreate();

  Future<SecretKey> deriveSharedSecret({required String remotePublicKey});

  Future<void> clear();
}

class SecureDeviceIdentityStore implements DeviceIdentityStore {
  static const _deviceIdKey = 'lifly.device.id.v1';
  static const _privateKey = 'lifly.device.x25519.private.v1';

  final SecretStore _secrets;
  final String Function() _newDeviceId;
  final X25519 _algorithm;

  SecureDeviceIdentityStore(
    this._secrets, {
    String Function()? newDeviceId,
    X25519? algorithm,
  }) : _newDeviceId = newDeviceId ?? const Uuid().v4,
       _algorithm = algorithm ?? X25519();

  @override
  Future<DeviceIdentity> loadOrCreate() async {
    final storedDeviceId = await _secrets.read(_deviceIdKey);
    final storedPrivateKey = await _secrets.read(_privateKey);
    if (storedDeviceId == null && storedPrivateKey == null) {
      return _create();
    }
    if (storedDeviceId == null ||
        storedDeviceId.isEmpty ||
        storedPrivateKey == null ||
        storedPrivateKey.isEmpty) {
      throw const DeviceIdentityCorrupt('Incomplete device identity');
    }
    final privateBytes = _decodePrivateKey(storedPrivateKey);
    return _identityFromPrivateKey(storedDeviceId, privateBytes);
  }

  @override
  Future<void> clear() async {
    await _secrets.delete(_privateKey);
    await _secrets.delete(_deviceIdKey);
  }

  @override
  Future<SecretKey> deriveSharedSecret({
    required String remotePublicKey,
  }) async {
    final encoded = await _secrets.read(_privateKey);
    if (encoded == null || encoded.isEmpty) {
      throw const DeviceIdentityCorrupt('Device private key is unavailable');
    }
    final privateBytes = _decodePrivateKey(encoded);
    final remoteBytes = _decodePublicKey(remotePublicKey);
    final keyPair = await _algorithm.newKeyPairFromSeed(privateBytes);
    try {
      return await _algorithm.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: SimplePublicKey(remoteBytes, type: KeyPairType.x25519),
      );
    } finally {
      privateBytes.fillRange(0, privateBytes.length, 0);
    }
  }

  Future<DeviceIdentity> _create() async {
    final deviceId = _newDeviceId();
    if (deviceId.isEmpty) {
      throw const DeviceIdentityCorrupt('Generated device id is empty');
    }
    final keyPair = await _algorithm.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    if (privateBytes.length != 32) {
      throw const DeviceIdentityCorrupt('Unexpected X25519 private key length');
    }
    final publicKey = await keyPair.extractPublicKey();
    await _secrets.write(_privateKey, base64Encode(privateBytes));
    await _secrets.write(_deviceIdKey, deviceId);
    return DeviceIdentity(
      deviceId: deviceId,
      publicKey: base64Encode(publicKey.bytes),
      keyVersion: 1,
    );
  }

  Future<DeviceIdentity> _identityFromPrivateKey(
    String deviceId,
    List<int> privateBytes,
  ) async {
    final keyPair = await _algorithm.newKeyPairFromSeed(privateBytes);
    final publicKey = await keyPair.extractPublicKey();
    return DeviceIdentity(
      deviceId: deviceId,
      publicKey: base64Encode(publicKey.bytes),
      keyVersion: 1,
    );
  }

  List<int> _decodePublicKey(String encoded) {
    try {
      final bytes = base64Decode(encoded);
      if (bytes.length != 32) {
        throw const DeviceIdentityCorrupt(
          'Unexpected X25519 public key length',
        );
      }
      return bytes;
    } on FormatException catch (error) {
      throw DeviceIdentityCorrupt('Invalid public key encoding: $error');
    }
  }

  List<int> _decodePrivateKey(String encoded) {
    try {
      final bytes = base64Decode(encoded);
      if (bytes.length != 32) {
        throw const DeviceIdentityCorrupt(
          'Unexpected X25519 private key length',
        );
      }
      return bytes;
    } on FormatException catch (error) {
      throw DeviceIdentityCorrupt('Invalid private key encoding: $error');
    }
  }
}
