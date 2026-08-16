import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/account_data_key_ring.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/crypto/encrypted_payload_cipher.dart';
import 'package:client_flutter/data/powersync/encrypted_projection_spec.dart';
import 'package:client_flutter/data/powersync/local_decrypted_projection.dart';
import 'package:client_flutter/data/powersync/local_mutation_committer.dart';
import 'package:client_flutter/data/powersync/powersync_view_writer.dart';
import 'package:powersync_sqlcipher/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';

class DecryptedSyncEntity {
  final String id;
  final String userId;
  final String entityType;
  final int revision;
  final EncryptedEntityLifecycleStatus lifecycleStatus;
  final DateTime updatedAt;
  final Map<String, Object?> payload;

  const DecryptedSyncEntity({
    required this.id,
    required this.userId,
    required this.entityType,
    required this.revision,
    required this.lifecycleStatus,
    required this.updatedAt,
    required this.payload,
  });
}

class EncryptedSyncState {
  final int envelopeCount;
  final int tombstoneCount;
  final int maxRevision;

  const EncryptedSyncState({
    required this.envelopeCount,
    required this.tombstoneCount,
    required this.maxRevision,
  });
}

class KeyRotationResult {
  final int rotated;
  final int skipped;
  final int keyVersion;

  const KeyRotationResult({
    required this.rotated,
    required this.skipped,
    required this.keyVersion,
  });
}

abstract interface class EncryptedSyncStore {
  Future<EncryptedEntityEnvelope> sealEntity(DecryptedSyncEntity entity);

  Future<EncryptedEntityEnvelope> putEncryptedEntity(
    DecryptedSyncEntity entity,
  );

  Future<ProjectionApplyResult> applyRemoteEnvelope(
    EncryptedEntityEnvelope envelope,
  );

  Stream<EncryptedSyncState> watchSyncState();

  Future<KeyRotationResult> rotateKey(AccountDataKey nextKey);
}

class PowerSyncEncryptedSyncStore implements EncryptedSyncStore {
  final PowerSyncDatabase db;
  final String accountId;
  final AccountDataKeyRing keyRing;
  final EncryptedPayloadCipher cipher;
  final LocalDecryptedProjection projection;

  PowerSyncEncryptedSyncStore({
    required this.db,
    required this.accountId,
    required this.keyRing,
    EncryptedPayloadCipher? cipher,
    LocalDecryptedProjection? projection,
  }) : cipher = cipher ?? EncryptedPayloadCipher(),
       projection = projection ?? LocalDecryptedProjection(db);

  @override
  Future<EncryptedEntityEnvelope> sealEntity(DecryptedSyncEntity entity) async {
    _requireAccount(entity.userId);
    if (entity.revision < 1) {
      throw ArgumentError.value(
        entity.revision,
        'revision',
        'must be positive',
      );
    }
    return cipher.encryptEntity(
      key: keyRing.current,
      id: entity.id,
      userId: accountId,
      entityType: entity.entityType,
      revision: entity.revision,
      lifecycleStatus: entity.lifecycleStatus,
      updatedAt: entity.updatedAt,
      payload: entity.payload,
    );
  }

  @override
  Future<EncryptedEntityEnvelope> putEncryptedEntity(
    DecryptedSyncEntity entity,
  ) async {
    _requireAccount(entity.userId);
    if (entity.revision < 1) {
      throw ArgumentError.value(
        entity.revision,
        'revision',
        'must be positive',
      );
    }
    final envelope = await sealEntity(entity);
    await db.writeTransaction((tx) async {
      final existingRevision = await _encryptedRevision(
        tx,
        entity.id,
        accountId,
      );
      if (existingRevision >= entity.revision) {
        throw StateError(
          'Encrypted entity ${entity.id} revision ${entity.revision} is not newer '
          'than local revision $existingRevision',
        );
      }
      await _upsertEnvelopeWithTransaction(tx, envelope);
      await projection.materializeWithTransaction(tx, envelope, entity.payload);
    });
    return envelope;
  }

  Future<int> materializePendingEnvelopes() async {
    final rows = await db.getAll(
      'SELECT e.id, e.user_id, e.entity_type, e.revision, e.lifecycle_status, '
      'e.updated_at, e.key_version, e.encryption_version, e.schema_version, '
      'e.nonce, e.ciphertext FROM encrypted_entities e '
      'LEFT JOIN e2ee_projection_state p '
      'ON p.id = e.id AND p.user_id = e.user_id '
      'WHERE e.user_id = ? AND (p.revision IS NULL OR p.revision < e.revision) '
      'ORDER BY e.updated_at, e.id',
      [accountId],
    );
    var applied = 0;
    for (final row in rows) {
      final result = await applyRemoteEnvelope(_envelopeFromRow(row));
      if (result.applied) applied += 1;
    }
    return applied;
  }

  @override
  Future<ProjectionApplyResult> applyRemoteEnvelope(
    EncryptedEntityEnvelope envelope,
  ) async {
    _requireAccount(envelope.userId);
    final key = keyRing.keyForVersion(envelope.keyVersion);
    if (key == null) {
      throw StateError(
        'Missing ADK version ${envelope.keyVersion} for ${envelope.id}',
      );
    }
    final payload = await cipher.decryptEntity(envelope, key: key);
    return projection.materialize(envelope, payload);
  }

  @override
  Stream<EncryptedSyncState> watchSyncState() {
    return db
        .watch(
          'SELECT COUNT(*) AS envelope_count, '
          "SUM(CASE WHEN lifecycle_status = 'tombstone' THEN 1 ELSE 0 END) AS tombstone_count, "
          'COALESCE(MAX(revision), 0) AS max_revision '
          'FROM encrypted_entities WHERE user_id = ?',
          parameters: [accountId],
          triggerOnTables: const ['encrypted_entities'],
        )
        .map((rows) {
          final row = rows.first;
          return EncryptedSyncState(
            envelopeCount: _intValue(row['envelope_count']) ?? 0,
            tombstoneCount: _intValue(row['tombstone_count']) ?? 0,
            maxRevision: _intValue(row['max_revision']) ?? 0,
          );
        });
  }

  @override
  Future<KeyRotationResult> rotateKey(AccountDataKey nextKey) async {
    if (nextKey.keyVersion <= keyRing.current.keyVersion) {
      throw ArgumentError.value(
        nextKey.keyVersion,
        'nextKey.keyVersion',
        'must be newer than current ADK version ${keyRing.current.keyVersion}',
      );
    }
    keyRing.add(nextKey);
    final rows = await db.getAll(
      'SELECT id, user_id, entity_type, revision, lifecycle_status, updated_at, '
      'key_version, encryption_version, schema_version, nonce, ciphertext '
      "FROM encrypted_entities WHERE user_id = ? AND lifecycle_status = 'active'",
      [accountId],
    );
    var rotated = 0;
    var skipped = 0;
    for (final row in rows) {
      final current = _envelopeFromRow(row);
      final oldKey = keyRing.keyForVersion(current.keyVersion);
      if (oldKey == null) {
        skipped += 1;
        continue;
      }
      final payload = await cipher.decryptEntity(current, key: oldKey);
      final rotatedEnvelope = await cipher.encryptEntity(
        key: nextKey,
        id: current.id,
        userId: current.userId,
        entityType: current.entityType,
        revision: current.revision + 1,
        lifecycleStatus: current.lifecycleStatus,
        updatedAt: DateTime.now().toUtc(),
        payload: payload,
      );
      await db.writeTransaction((tx) async {
        await _upsertEnvelopeWithTransaction(tx, rotatedEnvelope);
        await projection.materializeWithTransaction(
          tx,
          rotatedEnvelope,
          payload,
        );
      });
      rotated += 1;
    }
    keyRing.makeCurrent(nextKey.keyVersion);
    return KeyRotationResult(
      rotated: rotated,
      skipped: skipped,
      keyVersion: nextKey.keyVersion,
    );
  }

  Future<int> encryptedRevisionWithTransaction(
    SqliteWriteContext tx,
    String entityId,
  ) => _encryptedRevision(tx, entityId, accountId);

  Future<void> upsertEnvelopeWithTransaction(
    SqliteWriteContext tx,
    EncryptedEntityEnvelope envelope,
  ) async {
    _requireAccount(envelope.userId);
    await _upsertEnvelopeWithTransaction(tx, envelope);
  }

  Future<void> _upsertEnvelopeWithTransaction(
    SqliteWriteContext tx,
    EncryptedEntityEnvelope envelope,
  ) async {
    final existing = await tx.getOptional(
      'SELECT user_id, revision FROM encrypted_entities WHERE id = ?',
      [envelope.id],
    );
    if (existing != null) {
      final existingUserId = existing['user_id']?.toString() ?? '';
      if (existingUserId != envelope.userId) {
        throw StateError(
          'Encrypted entity id ${envelope.id} belongs to a different account',
        );
      }
      final existingRevision = _intValue(existing['revision']) ?? 0;
      if (existingRevision >= envelope.revision) return;
    }

    await insertOrUpdatePowerSyncView(
      tx,
      table: 'encrypted_entities',
      id: envelope.id,
      values: {
        'user_id': envelope.userId,
        'entity_type': envelope.entityType,
        'revision': envelope.revision,
        'lifecycle_status': envelope.lifecycleStatus.value,
        'updated_at': envelope.updatedAt.toUtc().toIso8601String(),
        'key_version': envelope.keyVersion,
        'encryption_version': envelope.encryptionVersion,
        'schema_version': liflyEncryptedEntitySchemaVersion,
        'nonce': envelope.nonce,
        'ciphertext': envelope.ciphertext,
      },
    );
  }

  void _requireAccount(String userId) {
    if (userId != accountId) {
      throw StateError(
        'EncryptedSyncStore account $accountId cannot access user $userId',
      );
    }
  }
}

/// Deep write seam between local decrypted projection tables and PowerSync's
/// synced encrypted envelope table. SQLite triggers record only entities touched
/// by the current write transaction; this committer seals those rows before the
/// transaction is allowed to commit.
class PowerSyncEncryptedLocalMutationCommitter
    implements LocalMutationCommitter {
  final PowerSyncEncryptedSyncStore store;

  const PowerSyncEncryptedLocalMutationCommitter(this.store);

  Future<void> initialize() async {
    for (final spec in encryptedProjectionSpecs) {
      await _installTriggers(spec);
    }
    // Drain mutations left by a previous application version. The historical
    // migrator runs before this initializer, so already-sealed revisions are
    // simply removed while a genuine pending delete is preserved as a tombstone.
    await store.db.writeTransaction(
      (transaction) => _commit(transaction, allowAlreadySealed: true),
    );
  }

  @override
  Future<void> commit(SqliteWriteContext transaction) =>
      _commit(transaction, allowAlreadySealed: false);

  Future<void> _commit(
    SqliteWriteContext transaction, {
    required bool allowAlreadySealed,
  }) async {
    final mutations = await transaction.getAll(
      'SELECT id, entity_id, user_id, entity_type, revision, lifecycle_status, updated_at '
      'FROM e2ee_local_mutations WHERE user_id = ? ORDER BY updated_at, id',
      [store.accountId],
    );
    for (final mutation in mutations) {
      final mutationId = mutation['id']?.toString() ?? '';
      final entityId = mutation['entity_id']?.toString() ?? '';
      final entityType = mutation['entity_type']?.toString() ?? '';
      final userId = mutation['user_id']?.toString() ?? '';
      final revision = _positiveInt(mutation['revision']);
      final updatedAt = DateTime.tryParse(
        mutation['updated_at']?.toString() ?? '',
      )?.toUtc();
      if (mutationId.isEmpty ||
          entityId.isEmpty ||
          entityType.isEmpty ||
          userId != store.accountId ||
          revision == null ||
          updatedAt == null) {
        throw StateError(
          'Invalid encrypted local mutation record: $mutationId',
        );
      }
      final spec = encryptedProjectionSpecByEntityType[entityType];
      if (spec == null) {
        throw StateError(
          'Unsupported encrypted local mutation type: $entityType',
        );
      }
      final existingRevision = await store.encryptedRevisionWithTransaction(
        transaction,
        entityId,
      );
      if (existingRevision >= revision) {
        if (allowAlreadySealed) {
          await _deleteMutation(transaction, mutationId);
          continue;
        }
        throw StateError(
          'Local $entityType/$entityId revision $revision did not advance '
          'past encrypted revision $existingRevision',
        );
      }

      var lifecycle = _lifecycleFromValue(mutation['lifecycle_status']);
      Map<String, Object?> payload = const {};
      if (lifecycle == EncryptedEntityLifecycleStatus.active) {
        final row = await transaction.getOptional(
          'SELECT * FROM ${spec.table} WHERE id = ? AND user_id = ?',
          [entityId, store.accountId],
        );
        if (row == null) {
          lifecycle = EncryptedEntityLifecycleStatus.tombstone;
        } else {
          payload = spec.payloadFromRow(row);
        }
      }

      final envelope = await store.sealEntity(
        DecryptedSyncEntity(
          id: entityId,
          userId: store.accountId,
          entityType: entityType,
          revision: revision,
          lifecycleStatus: lifecycle,
          updatedAt: updatedAt,
          payload: payload,
        ),
      );
      await store.upsertEnvelopeWithTransaction(transaction, envelope);
      await store.projection.recordMaterializedEnvelope(transaction, envelope);
      await _deleteMutation(transaction, mutationId);
    }
  }

  Future<void> _installTriggers(EncryptedProjectionSpec spec) async {
    final prefix = 'lifly_e2ee_${spec.table}';
    final backingTable = spec.localBackingTable;
    await _assertBackingTableShape(backingTable);

    final now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
    final mutationId = "'${spec.entityType}:' || NEW.id";
    final userId = "json_extract(NEW.data, '\$.user_id')";
    final revision =
        "CAST(COALESCE(json_extract(NEW.data, '\$.revision'), 1) AS INTEGER)";
    final updatedAt = "COALESCE(json_extract(NEW.data, '\$.updated_at'), $now)";
    final lifecycle = spec.triggerLifecycleExpressionFor('NEW');
    final replaceMarker =
        'DELETE FROM e2ee_local_mutations WHERE id = $mutationId; '
        'INSERT INTO e2ee_local_mutations('
        'id, entity_id, user_id, entity_type, revision, lifecycle_status, updated_at'
        ") VALUES ($mutationId, NEW.id, $userId, '${spec.entityType}', "
        "$revision, $lifecycle, $updatedAt);";

    for (final suffix in const ['insert', 'update', 'delete']) {
      await store.db.execute('DROP TRIGGER IF EXISTS ${prefix}_$suffix');
    }
    await store.db.execute(
      'CREATE TRIGGER ${prefix}_insert '
      'AFTER INSERT ON $backingTable BEGIN $replaceMarker END',
    );
    await store.db.execute(
      'CREATE TRIGGER ${prefix}_update '
      'AFTER UPDATE ON $backingTable BEGIN $replaceMarker END',
    );

    final oldUserId = "json_extract(OLD.data, '\$.user_id')";
    final oldRevision =
        "CAST(COALESCE(json_extract(OLD.data, '\$.revision'), 0) AS INTEGER) + 1";
    final oldMutationId = "'${spec.entityType}:' || OLD.id";
    await store.db.execute(
      'CREATE TRIGGER ${prefix}_delete '
      'AFTER DELETE ON $backingTable BEGIN '
      'DELETE FROM e2ee_local_mutations WHERE id = $oldMutationId; '
      'INSERT INTO e2ee_local_mutations('
      'id, entity_id, user_id, entity_type, revision, lifecycle_status, updated_at'
      ") VALUES ($oldMutationId, OLD.id, $oldUserId, '${spec.entityType}', "
      "$oldRevision, 'tombstone', $now); "
      'END',
    );
  }

  Future<void> _assertBackingTableShape(String backingTable) async {
    final columns = await store.db.getAll("PRAGMA table_info('$backingTable')");
    final names = columns.map((row) => row['name']?.toString()).toSet();
    if (!names.contains('id') || !names.contains('data')) {
      throw StateError(
        'Unsupported PowerSync local-only backing schema for $backingTable; '
        'expected id + data JSON columns',
      );
    }
  }

  Future<void> _deleteMutation(
    SqliteWriteContext transaction,
    String mutationId,
  ) => transaction.execute('DELETE FROM e2ee_local_mutations WHERE id = ?', [
    mutationId,
  ]);
}

Future<int> _encryptedRevision(
  SqliteReadContext db,
  String entityId,
  String accountId,
) async {
  final existing = await db.getOptional(
    'SELECT revision FROM encrypted_entities WHERE id = ? AND user_id = ?',
    [entityId, accountId],
  );
  return _intValue(existing?['revision']) ?? 0;
}

EncryptedEntityLifecycleStatus _lifecycleFromValue(Object? value) {
  return switch (value?.toString()) {
    'active' => EncryptedEntityLifecycleStatus.active,
    'tombstone' => EncryptedEntityLifecycleStatus.tombstone,
    _ => throw StateError('Invalid encrypted local mutation lifecycle: $value'),
  };
}

EncryptedEntityEnvelope _envelopeFromRow(Map<String, Object?> row) {
  return EncryptedEntityEnvelope.fromJson({
    'schema_version': _intValue(row['schema_version']) ?? 1,
    'id': row['id'],
    'user_id': row['user_id'],
    'entity_type': row['entity_type'],
    'revision': _intValue(row['revision']),
    'lifecycle_status': row['lifecycle_status'],
    'updated_at': row['updated_at'],
    'key_version': _intValue(row['key_version']),
    'encryption_version': _intValue(row['encryption_version']),
    'nonce': row['nonce'],
    'ciphertext': row['ciphertext'],
  });
}

int? _positiveInt(Object? value) {
  final parsed = _intValue(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
