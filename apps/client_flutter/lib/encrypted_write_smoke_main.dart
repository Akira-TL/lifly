import 'dart:convert';
import 'dart:io';

import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/account_data_key_ring.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';
import 'package:client_flutter/data/powersync/local_database_key.dart';
import 'package:client_flutter/data/powersync/plaintext_e2ee_migrator.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tempDir = await Directory.systemTemp.createTemp(
    'lifly-encrypted-write-smoke-',
  );
  var exitCode = 0;
  try {
    final dbPath = '${tempDir.path}/lifly.db';
    final syncService = SyncService(
      databaseKeyProvider: const FixedLocalDatabaseKeyProvider(
        'lifly-encrypted-write-smoke-db-key',
      ),
    );
    await syncService.initialize(dbPath: dbPath);
    try {
      final dataKey = AccountDataKey.fromBytes(
        keyVersion: 1,
        bytes: List<int>.generate(32, (index) => index + 1),
      );
      final store = PowerSyncEncryptedSyncStore(
        db: syncService.db,
        accountId: 'account-smoke',
        keyRing: AccountDataKeyRing(dataKey),
      );
      const legacy = 'LIFLY_LEGACY_PLAINTEXT_MIGRATION';
      await syncService.db.execute(
        'INSERT INTO memos('
        'id, user_id, type, content_markdown, source, status, created_at, updated_at, revision'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'memo-legacy-smoke',
          'account-smoke',
          'memo',
          legacy,
          'legacy',
          'active',
          '2026-08-16T07:00:00.000Z',
          '2026-08-16T07:00:00.000Z',
          1,
        ],
      );
      final migrator = PlaintextE2eeMigrator(
        db: syncService.db,
        store: store,
        accountId: 'account-smoke',
      );
      final firstMigration = await migrator.migrateCoreEntities();
      final secondMigration = await migrator.migrateCoreEntities();
      final legacyEnvelope = await syncService.db.getOptional(
        'SELECT ciphertext FROM encrypted_entities WHERE id = ?',
        ['memo-legacy-smoke'],
      );
      final migrationMarker = await syncService.db.getOptional(
        'SELECT migration_id FROM e2ee_migration_state WHERE account_id = ?',
        ['account-smoke'],
      );
      if (firstMigration.encrypted != 1 ||
          secondMigration.encrypted != 0 ||
          secondMigration.skipped != 0 ||
          legacyEnvelope == null ||
          (legacyEnvelope['ciphertext']?.toString() ?? '').contains(legacy) ||
          migrationMarker?['migration_id'] != plaintextE2eeCoreMigrationId) {
        throw StateError('one-time plaintext E2EE migration contract failed');
      }

      final committer = PowerSyncEncryptedLocalMutationCommitter(store);
      await committer.initialize();
      syncService.setLocalMutationCommitter(committer);

      const original = 'LIFLY_ENCRYPTED_WRITE_ORIGINAL';
      const stale = 'LIFLY_ENCRYPTED_WRITE_STALE';
      const updated = 'LIFLY_ENCRYPTED_WRITE_UPDATED';
      await syncService.writeLocalTransaction((tx) async {
        await tx.execute(
          'INSERT INTO memos('
          'id, user_id, type, content_markdown, source, status, created_at, updated_at, revision'
          ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'memo-smoke',
            'account-smoke',
            'memo',
            original,
            'smoke',
            'active',
            '2026-08-16T08:00:00.000Z',
            '2026-08-16T08:00:00.000Z',
            1,
          ],
        );
      });
      final envelopeV1 = await syncService.db.getOptional(
        'SELECT revision, ciphertext FROM encrypted_entities WHERE id = ?',
        ['memo-smoke'],
      );
      if (envelopeV1?['revision'] != 1) {
        throw StateError('revision 1 did not enter encrypted sync data plane');
      }
      final ciphertextV1 = envelopeV1?['ciphertext']?.toString() ?? '';
      if (ciphertextV1.isEmpty || ciphertextV1.contains(original)) {
        throw StateError('revision 1 ciphertext leaked plaintext');
      }

      var staleRejected = false;
      try {
        await syncService.writeLocalTransaction((tx) async {
          await tx.execute(
            'UPDATE memos SET content_markdown = ?, updated_at = ? WHERE id = ?',
            [stale, '2026-08-16T08:01:00.000Z', 'memo-smoke'],
          );
        });
      } on StateError {
        staleRejected = true;
      }
      if (!staleRejected) {
        throw StateError('same-revision local mutation was not rejected');
      }
      final rolledBack = await syncService.db.getOptional(
        'SELECT content_markdown, revision FROM memos WHERE id = ?',
        ['memo-smoke'],
      );
      if (rolledBack?['content_markdown'] != original ||
          rolledBack?['revision'] != 1) {
        throw StateError(
          'failed encrypted commit did not roll back local projection',
        );
      }
      final envelopeAfterRollback = await syncService.db.getOptional(
        'SELECT revision, ciphertext FROM encrypted_entities WHERE id = ?',
        ['memo-smoke'],
      );
      if (envelopeAfterRollback?['revision'] != 1 ||
          envelopeAfterRollback?['ciphertext'] != ciphertextV1) {
        throw StateError(
          'failed encrypted commit mutated the existing envelope',
        );
      }

      await syncService.writeLocalTransaction((tx) async {
        await tx.execute(
          'UPDATE memos SET content_markdown = ?, updated_at = ?, revision = ? WHERE id = ?',
          [updated, '2026-08-16T08:02:00.000Z', 2, 'memo-smoke'],
        );
      });
      final envelopeV2 = await syncService.db.getOptional(
        'SELECT revision, ciphertext FROM encrypted_entities WHERE id = ?',
        ['memo-smoke'],
      );
      if (envelopeV2?['revision'] != 2 ||
          envelopeV2?['ciphertext'] == ciphertextV1) {
        throw StateError('revision 2 did not publish a new encrypted envelope');
      }
      final queue = await syncService.db.getAll(
        'SELECT id FROM e2ee_local_mutations WHERE user_id = ?',
        ['account-smoke'],
      );
      if (queue.isNotEmpty) {
        throw StateError(
          'encrypted mutation queue was not drained transactionally',
        );
      }

      stdout.writeln(
        jsonEncode({
          'status': 'ok',
          'projection_envelope_atomic': true,
          'stale_revision_rejected': true,
          'rollback_verified': true,
          'encrypted_revision': 2,
          'plaintext_migration_once': true,
        }),
      );
    } finally {
      syncService.dispose();
    }
  } catch (error, stackTrace) {
    exitCode = 1;
    stderr.writeln('ENCRYPTED_WRITE_SMOKE_FAILED: $error');
    stderr.writeln(stackTrace);
  } finally {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
  exit(exitCode);
}
