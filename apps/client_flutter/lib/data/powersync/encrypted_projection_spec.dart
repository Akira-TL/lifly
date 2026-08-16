import 'package:client_flutter/data/crypto/encrypted_envelope.dart';

class EncryptedProjectionSpec {
  final String table;
  final String entityType;
  final List<String> payloadColumns;
  final String? lifecycleStatusColumn;

  const EncryptedProjectionSpec({
    required this.table,
    required this.entityType,
    required this.payloadColumns,
    this.lifecycleStatusColumn,
  });

  Set<String> get projectionColumns => {
    'user_id',
    ...payloadColumns,
    'revision',
    'updated_at',
  };

  Map<String, Object?> payloadFromRow(Map<String, Object?> row) {
    final payload = <String, Object?>{};
    for (final column in payloadColumns) {
      final value = row[column];
      if (value != null) payload[column] = value;
    }
    return payload;
  }

  EncryptedEntityLifecycleStatus lifecycleFromRow(Map<String, Object?> row) {
    final column = lifecycleStatusColumn;
    if (column != null && row[column]?.toString() == 'deleted') {
      return EncryptedEntityLifecycleStatus.tombstone;
    }
    return EncryptedEntityLifecycleStatus.active;
  }

  String get localBackingTable => 'ps_data_local__$table';

  String triggerLifecycleExpressionFor(String rowAlias) {
    final column = lifecycleStatusColumn;
    if (column == null) return "'active'";
    return "CASE WHEN json_extract($rowAlias.data, '\$.$column') = 'deleted' "
        "THEN 'tombstone' ELSE 'active' END";
  }
}

const encryptedProjectionSpecs = <EncryptedProjectionSpec>[
  EncryptedProjectionSpec(
    table: 'memos',
    entityType: 'memo',
    lifecycleStatusColumn: 'status',
    payloadColumns: [
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
    ],
  ),
  EncryptedProjectionSpec(
    table: 'tasks',
    entityType: 'task',
    lifecycleStatusColumn: 'status',
    payloadColumns: [
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
    ],
  ),
  EncryptedProjectionSpec(
    table: 'ledger_transactions',
    entityType: 'expense',
    lifecycleStatusColumn: 'status',
    payloadColumns: [
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
    ],
  ),
  EncryptedProjectionSpec(
    table: 'ledger_budgets',
    entityType: 'ledger_budget',
    lifecycleStatusColumn: 'status',
    payloadColumns: [
      'period_type',
      'period_key',
      'category_id',
      'amount',
      'currency',
      'alert_threshold',
      'status',
      'created_at',
    ],
  ),
  EncryptedProjectionSpec(
    table: 'reminders',
    entityType: 'reminder',
    payloadColumns: [
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
    ],
  ),
  EncryptedProjectionSpec(
    table: 'mcp_capture_sessions',
    entityType: 'capture_session',
    payloadColumns: [
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
    ],
  ),
  EncryptedProjectionSpec(
    table: 'mcp_capture_turns',
    entityType: 'capture_turn',
    payloadColumns: [
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
    ],
  ),
];

final encryptedProjectionSpecByEntityType = <String, EncryptedProjectionSpec>{
  for (final spec in encryptedProjectionSpecs) spec.entityType: spec,
};

final encryptedProjectionSpecByTable = <String, EncryptedProjectionSpec>{
  for (final spec in encryptedProjectionSpecs) spec.table: spec,
};

String encryptedLocalMutationId(String entityType, String entityId) =>
    '$entityType:$entityId';
