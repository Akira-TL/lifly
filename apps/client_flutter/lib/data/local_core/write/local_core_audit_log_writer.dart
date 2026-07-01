import 'dart:convert';

import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';

class LocalCoreAuditLogWriter {
  final LocalCoreWritePolicy policy;

  LocalCoreAuditLogWriter({LocalCoreWritePolicy? policy})
    : policy = policy ?? LocalCoreWritePolicy();

  Future<String> write(
    LocalCoreWriteHandle handle,
    LocalCoreAuditLogInput input,
  ) async {
    final id = policy.nextAuditLogId();
    final createdAt = policy.timestampsFor(input.context).createdAtIso;

    await handle.execute(
      'INSERT INTO audit_logs('
      'id, user_id, actor_type, actor_id, action, entity_type, entity_id, '
      'before_snapshot, after_snapshot, source_channel, source_text, tool_name, request_id, created_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        input.context.userId,
        input.context.actorTypeName,
        input.context.actorId,
        input.action,
        input.entityType,
        input.entityId,
        _encodeSnapshot(input.beforeSnapshot),
        _encodeSnapshot(input.afterSnapshot),
        input.context.sourceChannelName,
        input.context.sourceText,
        input.context.toolName,
        input.context.requestId,
        createdAt,
      ],
    );

    return id;
  }

  String? _encodeSnapshot(Map<String, Object?>? snapshot) {
    if (snapshot == null) return null;
    return jsonEncode(snapshot);
  }
}

class LocalCoreAuditLogInput {
  final LocalCoreContext context;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, Object?>? beforeSnapshot;
  final Map<String, Object?>? afterSnapshot;

  const LocalCoreAuditLogInput({
    required this.context,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.beforeSnapshot,
    this.afterSnapshot,
  });
}
