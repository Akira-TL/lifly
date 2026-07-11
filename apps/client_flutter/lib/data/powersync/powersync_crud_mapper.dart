import 'dart:convert';

import 'package:powersync/powersync.dart';

class SyncPushRequestPayload {
  final String clientId;
  final List<SyncPushChangePayload> changes;
  final int ignoredCount;

  const SyncPushRequestPayload({
    required this.clientId,
    required this.changes,
    required this.ignoredCount,
  });

  bool get hasChanges => changes.isNotEmpty;

  int get changeCount => changes.length;

  Map<String, Object?> toJson() {
    return {
      'client_id': clientId,
      'changes': changes.map((change) => change.toJson()).toList(),
    };
  }
}

class SyncPushChangePayload {
  final String entityType;
  final String operation;
  final String entityId;
  final String userId;
  final int revision;
  final DateTime? createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String source;
  final Map<String, Object?> data;

  const SyncPushChangePayload({
    required this.entityType,
    required this.operation,
    required this.entityId,
    required this.userId,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.source,
    required this.data,
  });

  Map<String, Object?> toJson() {
    return {
      'entity_type': entityType,
      'operation': operation,
      'entity_id': entityId,
      'user_id': userId,
      'revision': revision,
      if (createdAt != null) 'created_at': _toIso(createdAt!),
      'updated_at': _toIso(updatedAt),
      if (deletedAt != null) 'deleted_at': _toIso(deletedAt!),
      'source': source,
      'data': data,
    };
  }
}

class PowerSyncCrudMapper {
  static const Map<String, String> _entityTypeByTable = {
    'memos': 'memo',
    'tasks': 'task',
    'ledger_transactions': 'expense',
    'ledger_budgets': 'ledger_budget',
    'reminders': 'reminder',
    'mcp_capture_sessions': 'capture_session',
    'mcp_capture_turns': 'capture_turn',
  };

  static const Set<String> _jsonCollectionKeys = {
    'actions',
    'asset_ids',
    'selected_action_indexes',
    'result_entities',
  };

  static const Set<String> _metadataKeys = {
    'id',
    'user_id',
    'revision',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  const PowerSyncCrudMapper();

  SyncPushRequestPayload mapBatch(
    List<CrudEntry> entries, {
    required String clientId,
    String defaultUserId = 'local-dev',
    DateTime? fallbackNow,
  }) {
    final changes = <SyncPushChangePayload>[];
    var ignoredCount = 0;
    final now = (fallbackNow ?? DateTime.now()).toUtc();

    for (final entry in entries) {
      final change = mapEntry(
        entry,
        defaultUserId: defaultUserId,
        fallbackNow: now,
      );
      if (change == null) {
        ignoredCount += 1;
      } else {
        changes.add(change);
      }
    }

    return SyncPushRequestPayload(
      clientId: clientId,
      changes: changes,
      ignoredCount: ignoredCount,
    );
  }

  SyncPushChangePayload? mapEntry(
    CrudEntry entry, {
    String defaultUserId = 'local-dev',
    DateTime? fallbackNow,
  }) {
    final entityType = _entityTypeByTable[entry.table];
    if (entityType == null) return null;

    final data = _normalizeData(entry.opData);
    final now = (fallbackNow ?? DateTime.now()).toUtc();
    final updatedAt = _readDateTime(data['updated_at']) ?? now;
    final isDelete = entry.op == UpdateType.delete || _isSoftDelete(data);
    final deletedAt = isDelete
        ? (_readDateTime(data['deleted_at']) ?? updatedAt)
        : null;

    return SyncPushChangePayload(
      entityType: entityType,
      operation: isDelete ? 'delete' : 'upsert',
      entityId: entry.id,
      userId: _readString(data['user_id']) ?? defaultUserId,
      revision: _readPositiveInt(data['revision']) ?? entry.clientId,
      createdAt: _readDateTime(data['created_at']),
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      source: _readString(data['source']) ?? 'powersync',
      data: _cleanBusinessData(entityType, data),
    );
  }

  Map<String, Object?> _cleanBusinessData(
    String entityType,
    Map<String, Object?> data,
  ) {
    final cleaned = <String, Object?>{};
    for (final entry in data.entries) {
      if (_metadataKeys.contains(entry.key)) continue;
      cleaned[entry.key] = entry.key == 'tags'
          ? _normalizeTags(entry.value)
          : _jsonCollectionKeys.contains(entry.key)
          ? _normalizeJsonCollection(entry.value)
          : entry.value;
    }

    if (entityType == 'memo') {
      cleaned['tags'] = _normalizeTags(cleaned['tags']);
    }
    return cleaned;
  }

  Map<String, Object?> _normalizeData(Map<String, dynamic>? value) {
    if (value == null) return const {};
    return Map<String, Object?>.from(value);
  }

  bool _isSoftDelete(Map<String, Object?> data) {
    final status = _readString(data['status']);
    return status == 'deleted' || data['deleted_at'] != null;
  }

  Object? _normalizeJsonCollection(Object? value) {
    if (value == null) return const <Object?>[];
    if (value is List) return value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
      } catch (_) {
        return const <Object?>[];
      }
    }
    return const <Object?>[];
  }

  Object? _normalizeTags(Object? value) {
    if (value == null) return const <String>[];
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    if (value is String) {
      if (value.trim().isEmpty) return const <String>[];
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.whereType<String>().toList(growable: false);
        }
      } catch (_) {
        return const <String>[];
      }
    }
    return const <String>[];
  }
}

String? _readString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _readPositiveInt(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.parse(value.replaceFirst('Z', '+00:00')).toUtc();
  }
  return null;
}

String _toIso(DateTime value) => value.toUtc().toIso8601String();
