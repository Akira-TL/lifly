import 'dart:convert';

import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/crypto/secure_local_database_key_provider.dart';
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
    'local database key is generated once and persisted only in SecretStore',
    () async {
      final secrets = _MemorySecrets();
      final provider = SecureLocalDatabaseKeyProvider(secrets: secrets);

      final first = await provider.loadOrCreateKey();
      final second = await provider.loadOrCreateKey();

      expect(second, first);
      final padding = (4 - first.length % 4) % 4;
      final bytes = base64Url.decode(
        '$first${List<String>.filled(padding, '=').join()}',
      );
      expect(bytes, hasLength(32));
      expect(secrets.values.keys, contains('lifly.db.sqlcipher.key.v1'));
      expect(secrets.values.values.single, first);
    },
  );

  test(
    'corrupt stored database key fails closed instead of rotating silently',
    () async {
      final secrets = _MemorySecrets()
        ..values['lifly.db.sqlcipher.key.v1'] = base64Url.encode([1, 2, 3]);
      final provider = SecureLocalDatabaseKeyProvider(secrets: secrets);

      await expectLater(provider.loadOrCreateKey(), throwsA(isA<StateError>()));
    },
  );
}
