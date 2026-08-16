import 'dart:convert';

import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/powersync/local_database_key.dart';
import 'package:cryptography/cryptography.dart';

class SecureLocalDatabaseKeyProvider implements LocalDatabaseKeyProvider {
  static const String _storageKey = 'lifly.db.sqlcipher.key.v1';

  final SecretStore secrets;
  final Cipher cipher;

  SecureLocalDatabaseKeyProvider({required this.secrets, Cipher? cipher})
    : cipher = cipher ?? AesGcm.with256bits();

  @override
  Future<String> loadOrCreateKey() async {
    final stored = await secrets.read(_storageKey);
    if (stored != null && stored.isNotEmpty) {
      final bytes = _decode(stored);
      if (bytes.length != 32) {
        throw StateError('Stored local database encryption key is invalid');
      }
      return _encode(bytes);
    }

    final key = await cipher.newSecretKey();
    final bytes = await key.extractBytes();
    if (bytes.length != 32) {
      throw StateError('Generated local database encryption key is invalid');
    }
    final encoded = _encode(bytes);
    await secrets.write(_storageKey, encoded);
    return encoded;
  }

  String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceFirst(RegExp(r'=+$'), '');

  List<int> _decode(String value) {
    final padding = (4 - value.length % 4) % 4;
    return base64Url.decode('$value${List.filled(padding, '=').join()}');
  }
}
