import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/account_data_key_ring.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/crypto/encrypted_payload_cipher.dart';
import 'package:client_flutter/data/powersync/local_decrypted_projection.dart';
import 'package:powersync/powersync.dart';

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
    final existing = await db.getOptional(
      'SELECT revision FROM encrypted_entities WHERE id = ? AND user_id = ?',
      [entity.id, accountId],
    );
    final existingRevision = _intValue(existing?['revision']) ?? 0;
    if (existingRevision >= entity.revision) {
      throw StateError(
        'Encrypted entity ${entity.id} revision ${entity.revision} is not newer '
        'than local revision $existingRevision',
      );
    }

    final envelope = await sealEntity(entity);
    await _upsertEnvelope(envelope);
    await projection.materialize(envelope, entity.payload);
    return envelope;
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
      await _upsertEnvelope(rotatedEnvelope);
      await projection.materialize(rotatedEnvelope, payload);
      rotated += 1;
    }
    keyRing.makeCurrent(nextKey.keyVersion);
    return KeyRotationResult(
      rotated: rotated,
      skipped: skipped,
      keyVersion: nextKey.keyVersion,
    );
  }

  Future<void> _upsertEnvelope(EncryptedEntityEnvelope envelope) async {
    final existing = await db.getOptional(
      'SELECT id FROM encrypted_entities WHERE id = ? AND user_id = ?',
      [envelope.id, envelope.userId],
    );
    final values = [
      envelope.userId,
      envelope.entityType,
      envelope.revision,
      envelope.lifecycleStatus.value,
      envelope.updatedAt.toUtc().toIso8601String(),
      envelope.keyVersion,
      envelope.encryptionVersion,
      liflyEncryptedEntitySchemaVersion,
      envelope.nonce,
      envelope.ciphertext,
    ];
    if (existing == null) {
      await db.execute(
        'INSERT INTO encrypted_entities('
        'id, user_id, entity_type, revision, lifecycle_status, updated_at, '
        'key_version, encryption_version, schema_version, nonce, ciphertext'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [envelope.id, ...values],
      );
      return;
    }
    await db.execute(
      'UPDATE encrypted_entities SET '
      'user_id = ?, entity_type = ?, revision = ?, lifecycle_status = ?, '
      'updated_at = ?, key_version = ?, encryption_version = ?, '
      'schema_version = ?, nonce = ?, ciphertext = ? '
      'WHERE id = ?',
      [...values, envelope.id],
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

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
