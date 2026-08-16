import 'dart:convert';

import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/powersync/encrypted_projection_spec.dart';
import 'package:client_flutter/data/powersync/powersync_view_writer.dart';
import 'package:powersync_sqlcipher/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';

class ProjectionApplyResult {
  final bool applied;
  final String? reason;
  final int revision;

  const ProjectionApplyResult.applied(this.revision)
    : applied = true,
      reason = null;

  const ProjectionApplyResult.skipped(this.revision, this.reason)
    : applied = false;
}

class LocalDecryptedProjection {
  final PowerSyncDatabase db;

  const LocalDecryptedProjection(this.db);

  Future<ProjectionApplyResult> materialize(
    EncryptedEntityEnvelope envelope,
    Map<String, Object?> payload,
  ) {
    return db.writeTransaction(
      (tx) => materializeWithTransaction(tx, envelope, payload),
    );
  }

  Future<ProjectionApplyResult> materializeWithTransaction(
    SqliteWriteContext tx,
    EncryptedEntityEnvelope envelope,
    Map<String, Object?> payload,
  ) async {
    final spec = encryptedProjectionSpecByEntityType[envelope.entityType];
    if (spec == null) {
      return ProjectionApplyResult.skipped(
        envelope.revision,
        'unsupported_entity_type',
      );
    }

    final current = await tx.getOptional(
      'SELECT revision FROM e2ee_projection_state WHERE id = ? AND user_id = ?',
      [envelope.id, envelope.userId],
    );
    final currentRevision = _intValue(current?['revision']) ?? 0;
    if (currentRevision >= envelope.revision) {
      return ProjectionApplyResult.skipped(currentRevision, 'stale_revision');
    }

    if (envelope.lifecycleStatus == EncryptedEntityLifecycleStatus.tombstone) {
      await tx.execute('DELETE FROM ${spec.table} WHERE id = ?', [envelope.id]);
    } else {
      final values = <String, Object?>{};
      for (final column in spec.projectionColumns) {
        if (payload.containsKey(column)) {
          values[column] = _sqliteValue(payload[column]);
        }
      }
      values['user_id'] = envelope.userId;
      values['revision'] = envelope.revision;
      values['updated_at'] = envelope.updatedAt.toUtc().toIso8601String();
      if (spec.table == 'mcp_capture_sessions' &&
          !values.containsKey('capture_id')) {
        values['capture_id'] = envelope.id;
      }
      await _upsert(tx, spec.table, envelope.id, values);
    }

    await recordMaterializedEnvelope(tx, envelope);
    await tx.execute('DELETE FROM e2ee_local_mutations WHERE id = ?', [
      encryptedLocalMutationId(envelope.entityType, envelope.id),
    ]);
    return ProjectionApplyResult.applied(envelope.revision);
  }

  Future<void> recordMaterializedEnvelope(
    SqliteWriteContext tx,
    EncryptedEntityEnvelope envelope,
  ) async {
    final existing = await tx.getOptional(
      'SELECT user_id, revision FROM e2ee_projection_state WHERE id = ?',
      [envelope.id],
    );
    if (existing != null) {
      final existingUserId = existing['user_id']?.toString() ?? '';
      if (existingUserId != envelope.userId) {
        throw StateError(
          'Projection state id ${envelope.id} belongs to a different account',
        );
      }
      final revision = _intValue(existing['revision']) ?? 0;
      if (revision >= envelope.revision) return;
    }
    await insertOrUpdatePowerSyncView(
      tx,
      table: 'e2ee_projection_state',
      id: envelope.id,
      values: {
        'user_id': envelope.userId,
        'entity_type': envelope.entityType,
        'revision': envelope.revision,
        'key_version': envelope.keyVersion,
        'lifecycle_status': envelope.lifecycleStatus.value,
        'updated_at': envelope.updatedAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _upsert(
    SqliteWriteContext tx,
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    if (values.isEmpty) {
      throw StateError('Cannot materialize an empty projection for $table/$id');
    }
    await insertOrUpdatePowerSyncView(tx, table: table, id: id, values: values);
  }
}

Object? _sqliteValue(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is bool) return value ? 1 : 0;
  if (value is List || value is Map) return jsonEncode(value);
  return value;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
