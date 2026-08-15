import 'package:cryptography/cryptography.dart';

class AccountDataKey {
  static const int byteLength = 32;

  final int keyVersion;
  final SecretKey secretKey;

  const AccountDataKey({required this.keyVersion, required this.secretKey});

  factory AccountDataKey.fromBytes({
    required int keyVersion,
    required List<int> bytes,
  }) {
    if (keyVersion < 1) {
      throw ArgumentError.value(keyVersion, 'keyVersion', 'must be positive');
    }
    if (bytes.length != byteLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'Account Data Key must be exactly $byteLength bytes',
      );
    }
    return AccountDataKey(
      keyVersion: keyVersion,
      secretKey: SecretKey(List<int>.from(bytes)),
    );
  }

  static Future<AccountDataKey> generate({required int keyVersion}) async {
    if (keyVersion < 1) {
      throw ArgumentError.value(keyVersion, 'keyVersion', 'must be positive');
    }
    final secretKey = await AesGcm.with256bits().newSecretKey();
    return AccountDataKey(keyVersion: keyVersion, secretKey: secretKey);
  }

  Future<List<int>> extractBytes() => secretKey.extractBytes();
}
