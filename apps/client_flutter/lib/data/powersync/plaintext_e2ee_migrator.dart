import 'package:client_flutter/data/powersync/encrypted_projection_spec.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';
import 'package:client_flutter/data/powersync/powersync_view_writer.dart';
import 'package:powersync_sqlcipher/powersync.dart';

class PlaintextE2eeMigrationResult {
  final int encrypted;
  final int skipped;

  const PlaintextE2eeMigrationResult({
    required this.encrypted,
    required this.skipped,
  });
}

/// One-time compatibility path for rows created before the encrypted write seam.
///
/// Normal Local Core writes must never call this migrator. They are encrypted in
/// the same SQLite transaction by [PowerSyncEncryptedLocalMutationCommitter].
const String plaintextE2eeCoreMigrationId = 'plaintext-e2ee-core-v1';

class PlaintextE2eeMigrator {
  final PowerSyncDatabase db;
  final PowerSyncEncryptedSyncStore store;
  final String accountId;

  const PlaintextE2eeMigrator({
    required this.db,
    required this.store,
    required this.accountId,
  });

  Future<PlaintextE2eeMigrationResult> migrateCoreEntities() async {
    final markerId = '$plaintextE2eeCoreMigrationId:$accountId';
    final completed = await db.getOptional(
      'SELECT id FROM e2ee_migration_state WHERE id = ? AND account_id = ?',
      [markerId, accountId],
    );
    if (completed != null) {
      return const PlaintextE2eeMigrationResult(encrypted: 0, skipped: 0);
    }

    var encrypted = 0;
    var skipped = 0;

    for (final spec in encryptedProjectionSpecs) {
      final rows = await db.getAll(
        'SELECT * FROM ${spec.table} WHERE user_id = ?',
        [accountId],
      );
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) {
          skipped += 1;
          continue;
        }
        final revision = _positiveInt(row['revision']) ?? 1;
        final existing = await db.getOptional(
          'SELECT revision FROM encrypted_entities WHERE id = ? AND user_id = ?',
          [id, accountId],
        );
        if ((_positiveInt(existing?['revision']) ?? 0) >= revision) {
          skipped += 1;
          continue;
        }

        await store.putEncryptedEntity(
          DecryptedSyncEntity(
            id: id,
            userId: accountId,
            entityType: spec.entityType,
            revision: revision,
            lifecycleStatus: spec.lifecycleFromRow(row),
            updatedAt:
                _dateTimeValue(row['updated_at']) ?? DateTime.now().toUtc(),
            payload: spec.payloadFromRow(row),
          ),
        );
        encrypted += 1;
      }
    }

    await insertOrUpdatePowerSyncView(
      db,
      table: 'e2ee_migration_state',
      id: markerId,
      values: {
        'account_id': accountId,
        'migration_id': plaintextE2eeCoreMigrationId,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return PlaintextE2eeMigrationResult(encrypted: encrypted, skipped: skipped);
  }
}

int? _positiveInt(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  final parsed = int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

DateTime? _dateTimeValue(Object? value) {
  if (value is DateTime) return value.toUtc();
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc();
}
