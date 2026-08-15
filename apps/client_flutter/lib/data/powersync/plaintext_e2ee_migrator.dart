import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';
import 'package:powersync/powersync.dart';

class PlaintextE2eeMigrationResult {
  final int encrypted;
  final int skipped;

  const PlaintextE2eeMigrationResult({
    required this.encrypted,
    required this.skipped,
  });
}

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
    var encrypted = 0;
    var skipped = 0;

    for (final spec in _migrationSpecs) {
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

        final payload = <String, Object?>{};
        for (final column in spec.payloadColumns) {
          final value = row[column];
          if (value != null) payload[column] = value;
        }
        final status = row['status']?.toString();
        final lifecycle = status == 'deleted'
            ? EncryptedEntityLifecycleStatus.tombstone
            : EncryptedEntityLifecycleStatus.active;
        final updatedAt =
            _dateTimeValue(row['updated_at']) ?? DateTime.now().toUtc();

        await store.putEncryptedEntity(
          DecryptedSyncEntity(
            id: id,
            userId: accountId,
            entityType: spec.entityType,
            revision: revision,
            lifecycleStatus: lifecycle,
            updatedAt: updatedAt,
            payload: payload,
          ),
        );
        encrypted += 1;
      }
    }

    return PlaintextE2eeMigrationResult(encrypted: encrypted, skipped: skipped);
  }
}

class _MigrationSpec {
  final String table;
  final String entityType;
  final List<String> payloadColumns;

  const _MigrationSpec(this.table, this.entityType, this.payloadColumns);
}

const _migrationSpecs = <_MigrationSpec>[
  _MigrationSpec('memos', 'memo', [
    'type',
    'title',
    'content_markdown',
    'tags',
    'mood',
    'source_capture_id',
    'source',
    'status',
    'created_at',
    'deleted_at',
  ]),
  _MigrationSpec('tasks', 'task', [
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
    'completed_at',
    'deleted_at',
  ]),
  _MigrationSpec('ledger_transactions', 'expense', [
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
    'deleted_at',
  ]),
  _MigrationSpec('ledger_budgets', 'ledger_budget', [
    'period_type',
    'period_key',
    'category_id',
    'amount',
    'currency',
    'alert_threshold',
    'status',
    'created_at',
  ]),
  _MigrationSpec('reminders', 'reminder', [
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
    'created_at',
  ]),
  _MigrationSpec('mcp_capture_sessions', 'capture_session', [
    'capture_id',
    'original_text',
    'timezone',
    'locale',
    'actions',
    'requires_confirmation',
    'committed',
    'session_status',
    'source_channel',
    'created_at',
    'expires_at',
    'committed_at',
    'dismissed_at',
  ]),
  _MigrationSpec('mcp_capture_turns', 'capture_turn', [
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
  ]),
];

int? _positiveInt(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _dateTimeValue(Object? value) {
  if (value is DateTime) return value.toUtc();
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc();
}
