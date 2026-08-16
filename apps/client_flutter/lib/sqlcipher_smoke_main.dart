import 'dart:convert';
import 'dart:io';

import 'package:client_flutter/data/powersync/local_database_key.dart';
import 'package:client_flutter/data/powersync/powersync_schema.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter/widgets.dart';
import 'package:powersync_sqlcipher/powersync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tempDir = await Directory.systemTemp.createTemp(
    'lifly-sqlcipher-smoke-',
  );
  var resultCode = 0;
  try {
    await _verifyFreshEncryptedDatabase(tempDir);
    await _verifyPlaintextUpgrade(tempDir);
    stdout.writeln(
      jsonEncode({
        'status': 'ok',
        'encrypted_at_rest': true,
        'same_key_reopen': true,
        'wrong_key_rejected': true,
        'plaintext_upgrade_rekeyed': true,
      }),
    );
  } catch (error, stackTrace) {
    resultCode = 1;
    stderr.writeln('SQLCIPHER_SMOKE_FAILED: $error');
    stderr.writeln(stackTrace);
  } finally {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
  exit(resultCode);
}

Future<void> _verifyFreshEncryptedDatabase(Directory tempDir) async {
  final dbPath = '${tempDir.path}/lifly.db';
  const key = 'lifly-runtime-sqlcipher-smoke-key-v1';
  const marker = 'LIFLY_SQLCIPHER_PLAINTEXT_MARKER';

  final first = SyncService(
    databaseKeyProvider: const FixedLocalDatabaseKeyProvider(key),
  );
  await first.initialize(dbPath: dbPath);
  await first.db.execute(
    'INSERT INTO memos('
    'id, user_id, type, content_markdown, source, status, created_at, updated_at, revision'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      'sqlcipher-smoke-memo',
      'sqlcipher-smoke-account',
      'memo',
      marker,
      'system',
      'active',
      '2026-08-16T08:00:00.000Z',
      '2026-08-16T08:00:00.000Z',
      1,
    ],
  );
  first.dispose();

  await _requireEncryptedDisk(dbPath, marker);

  final reopened = SyncService(
    databaseKeyProvider: const FixedLocalDatabaseKeyProvider(key),
  );
  await reopened.initialize(dbPath: dbPath);
  final row = await reopened.db.getOptional(
    'SELECT content_markdown FROM memos WHERE id = ?',
    ['sqlcipher-smoke-memo'],
  );
  if (row?['content_markdown'] != marker) {
    throw StateError('SQLCipher database did not reopen with the original key');
  }
  reopened.dispose();

  var wrongKeyRejected = false;
  final wrongKey = SyncService(
    databaseKeyProvider: const FixedLocalDatabaseKeyProvider(
      'lifly-runtime-sqlcipher-wrong-key',
    ),
  );
  try {
    await wrongKey.initialize(dbPath: dbPath);
  } catch (_) {
    wrongKeyRejected = true;
  } finally {
    wrongKey.dispose();
  }
  if (!wrongKeyRejected) {
    throw StateError('SQLCipher database opened with the wrong key');
  }
}

Future<void> _verifyPlaintextUpgrade(Directory tempDir) async {
  final legacyPath = '${tempDir.path}/legacy-plaintext.db';
  const migratedKey = 'lifly-runtime-sqlcipher-migrated-key-v1';
  const marker = 'LIFLY_LEGACY_PLAINTEXT_MARKER';

  final plaintextFactory = PowerSyncOpenFactory(path: legacyPath);
  final legacyDb = PowerSyncDatabase.withFactory(
    plaintextFactory,
    schema: liflyPowerSyncSchema,
  );
  await legacyDb.initialize();
  await legacyDb.execute(
    'INSERT INTO memos('
    'id, user_id, type, content_markdown, source, status, created_at, updated_at, revision'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      'legacy-memo',
      'legacy-account',
      'memo',
      marker,
      'system',
      'active',
      '2026-08-16T08:00:00.000Z',
      '2026-08-16T08:00:00.000Z',
      1,
    ],
  );
  await legacyDb.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  legacyDb.close();

  final before = await File(legacyPath).readAsBytes();
  if (!_hasPlainSqliteHeader(before)) {
    throw StateError('Plaintext upgrade fixture was unexpectedly encrypted');
  }
  if (!utf8.decode(before, allowMalformed: true).contains(marker)) {
    throw StateError('Plaintext upgrade fixture did not contain its marker');
  }

  final migrated = SyncService(
    databaseKeyProvider: const FixedLocalDatabaseKeyProvider(migratedKey),
  );
  await migrated.initialize(dbPath: legacyPath);
  final row = await migrated.db.getOptional(
    'SELECT content_markdown FROM memos WHERE id = ?',
    ['legacy-memo'],
  );
  if (row?['content_markdown'] != marker) {
    throw StateError('Plaintext database migration lost local projection data');
  }
  migrated.dispose();
  await _requireEncryptedDisk(legacyPath, marker);
}

Future<void> _requireEncryptedDisk(String path, String marker) async {
  final bytes = await File(path).readAsBytes();
  final diskText = utf8.decode(bytes, allowMalformed: true);
  if (diskText.contains(marker)) {
    throw StateError('SQLCipher database leaked plaintext marker');
  }
  if (_hasPlainSqliteHeader(bytes)) {
    throw StateError('SQLCipher database retained plaintext SQLite header');
  }
}

bool _hasPlainSqliteHeader(List<int> bytes) {
  final expected = utf8.encode('SQLite format 3\u0000');
  if (bytes.length < expected.length) return false;
  for (var index = 0; index < expected.length; index += 1) {
    if (bytes[index] != expected[index]) return false;
  }
  return true;
}
