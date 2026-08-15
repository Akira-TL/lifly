import 'dart:convert';

import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:powersync/powersync.dart';

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
  ) async {
    final spec = _projectionSpecs[envelope.entityType];
    if (spec == null) {
      return ProjectionApplyResult.skipped(
        envelope.revision,
        'unsupported_entity_type',
      );
    }

    final current = await db.getOptional(
      'SELECT revision FROM e2ee_projection_state WHERE id = ? AND user_id = ?',
      [envelope.id, envelope.userId],
    );
    final currentRevision = _intValue(current?['revision']) ?? 0;
    if (currentRevision >= envelope.revision) {
      return ProjectionApplyResult.skipped(currentRevision, 'stale_revision');
    }

    if (envelope.lifecycleStatus == EncryptedEntityLifecycleStatus.tombstone) {
      await db.execute('DELETE FROM ${spec.table} WHERE id = ?', [envelope.id]);
    } else {
      final values = <String, Object?>{};
      for (final column in spec.columns) {
        if (payload.containsKey(column)) {
          values[column] = _sqliteValue(payload[column]);
        }
      }
      values['user_id'] = envelope.userId;
      if (spec.columns.contains('revision')) {
        values['revision'] = envelope.revision;
      }
      if (spec.columns.contains('updated_at')) {
        values['updated_at'] = envelope.updatedAt.toUtc().toIso8601String();
      }
      if (spec.table == 'mcp_capture_sessions' &&
          !values.containsKey('capture_id')) {
        values['capture_id'] = envelope.id;
      }
      await _upsert(spec.table, envelope.id, values);
    }

    final stateValues = [
      envelope.userId,
      envelope.entityType,
      envelope.revision,
      envelope.keyVersion,
      envelope.lifecycleStatus.value,
      envelope.updatedAt.toUtc().toIso8601String(),
    ];
    if (current == null) {
      await db.execute(
        'INSERT INTO e2ee_projection_state('
        'id, user_id, entity_type, revision, key_version, lifecycle_status, updated_at'
        ') VALUES (?, ?, ?, ?, ?, ?, ?)',
        [envelope.id, ...stateValues],
      );
    } else {
      await db.execute(
        'UPDATE e2ee_projection_state SET '
        'user_id = ?, entity_type = ?, revision = ?, key_version = ?, '
        'lifecycle_status = ?, updated_at = ? WHERE id = ?',
        [...stateValues, envelope.id],
      );
    }
    return ProjectionApplyResult.applied(envelope.revision);
  }

  Future<void> _upsert(
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    if (values.isEmpty) {
      throw StateError('Cannot materialize an empty projection for $table/$id');
    }
    final columns = values.keys.toList(growable: false);
    final row = await db.getOptional('SELECT id FROM $table WHERE id = ?', [
      id,
    ]);
    if (row == null) {
      final placeholders = List.filled(columns.length + 1, '?').join(', ');
      await db.execute(
        'INSERT INTO $table(id, ${columns.join(', ')}) VALUES ($placeholders)',
        [id, ...columns.map((column) => values[column])],
      );
      return;
    }
    final assignments = columns.map((column) => '$column = ?').join(', ');
    await db.execute('UPDATE $table SET $assignments WHERE id = ?', [
      ...columns.map((column) => values[column]),
      id,
    ]);
  }
}

class _ProjectionSpec {
  final String table;
  final Set<String> columns;

  const _ProjectionSpec(this.table, this.columns);
}

const _projectionSpecs = <String, _ProjectionSpec>{
  'memo': _ProjectionSpec('memos', {
    'user_id',
    'type',
    'title',
    'content_markdown',
    'tags',
    'mood',
    'source_capture_id',
    'source',
    'status',
    'created_at',
    'updated_at',
    'deleted_at',
    'revision',
  }),
  'task': _ProjectionSpec('tasks', {
    'user_id',
    'title',
    'description',
    'due_at',
    'remind_at',
    'priority',
    'task_status',
    'source_capture_id',
    'source',
    'status',
    'created_at',
    'updated_at',
    'completed_at',
    'deleted_at',
    'revision',
  }),
  'expense': _ProjectionSpec('ledger_transactions', {
    'user_id',
    'account_id',
    'category_id',
    'direction',
    'amount',
    'currency',
    'merchant',
    'note',
    'occurred_at',
    'source',
    'source_capture_id',
    'import_batch_id',
    'confidence',
    'status',
    'created_at',
    'updated_at',
    'deleted_at',
    'revision',
  }),
  'ledger_budget': _ProjectionSpec('ledger_budgets', {
    'user_id',
    'period_type',
    'period_key',
    'category_id',
    'amount',
    'currency',
    'alert_threshold',
    'status',
    'revision',
    'created_at',
    'updated_at',
  }),
  'reminder': _ProjectionSpec('reminders', {
    'user_id',
    'target_type',
    'target_id',
    'remind_at',
    'channel',
    'reminder_status',
    'attempt_count',
    'max_attempts',
    'next_attempt_at',
    'last_attempt_at',
    'delivered_at',
    'failed_at',
    'cancelled_at',
    'last_error',
    'external_id',
    'dispatch_token',
    'lease_until',
    'revision',
    'created_at',
    'updated_at',
  }),
  'capture_session': _ProjectionSpec('mcp_capture_sessions', {
    'capture_id',
    'user_id',
    'original_text',
    'timezone',
    'locale',
    'actions',
    'requires_confirmation',
    'committed',
    'session_status',
    'source_channel',
    'created_at',
    'updated_at',
    'expires_at',
    'committed_at',
    'dismissed_at',
    'revision',
  }),
  'capture_turn': _ProjectionSpec('mcp_capture_turns', {
    'user_id',
    'capture_id',
    'turn_index',
    'role',
    'text',
    'asset_ids',
    'asset_context',
    'actions',
    'selected_action_indexes',
    'result_entities',
    'undo_token',
    'supersedes_turn_id',
    'turn_status',
    'source_channel',
    'created_at',
    'updated_at',
    'revision',
  }),
};

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
