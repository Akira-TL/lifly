import 'dart:convert';

import 'package:client_flutter/data/local_core/ledger/powersync_expense_store.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/memo/powersync_memo_store.dart';
import 'package:client_flutter/data/local_core/task/powersync_task_store.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

class PowerSyncCaptureStore {
  final SyncService syncService;
  final PowerSyncMemoStore memoStore;
  final PowerSyncTaskStore taskStore;
  final PowerSyncExpenseStore expenseStore;
  final LocalCoreWritePolicy policy;

  PowerSyncCaptureStore({
    required this.syncService,
    required this.memoStore,
    required this.taskStore,
    required this.expenseStore,
    LocalCoreWritePolicy? policy,
  }) : policy = policy ?? LocalCoreWritePolicy();

  Future<LocalCaptureSession> captureParse(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final text = _readRequiredString(input, 'text');
    final timezone = _readOptionalString(input, 'timezone') ?? 'Asia/Shanghai';
    final locale = _readOptionalString(input, 'locale') ?? 'zh-CN';
    final assetIds = _readStringList(input, 'asset_ids');
    final now = context.effectiveNow.toUtc();
    final captureId = policy.nextEntityId('capture');
    final expiresAt = now.add(const Duration(hours: 24));
    final action = LocalCaptureAction(
      type: 'memo_create',
      payload: {
        'type': 'memo',
        'title': null,
        'content_markdown': text,
        'tags': ['capture'],
        'source_capture_id': captureId,
        if (assetIds.isNotEmpty) 'asset_ids': assetIds,
      },
      confidence: 0.45,
      rawText: text,
    );
    final turn = LocalCaptureTurn(
      id: policy.nextEntityId('capture_turn'),
      captureId: captureId,
      turnIndex: 0,
      role: 'assistant',
      text: text,
      actions: [action],
      selectedActionIndexes: const [],
      resultEntities: const [],
      turnStatus: 'parsed',
      createdAt: now,
      updatedAt: now,
    );
    final session = LocalCaptureSession(
      captureId: captureId,
      originalText: text,
      timezone: timezone,
      locale: locale,
      actions: [action],
      requiresConfirmation: true,
      sessionStatus: 'parsed',
      sourceChannel: context.sourceChannelName,
      createdAt: now,
      updatedAt: now,
      expiresAt: expiresAt,
      turns: [turn],
    );

    await syncService.ensureInitialized();
    await syncService.db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO mcp_capture_sessions('
        'id, capture_id, user_id, original_text, timezone, locale, actions, requires_confirmation, '
        'session_status, source_channel, created_at, updated_at, expires_at'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          session.captureId,
          session.captureId,
          context.userId,
          session.originalText,
          session.timezone,
          session.locale,
          _encodeActions(session.actions),
          session.requiresConfirmation ? 1 : 0,
          session.sessionStatus,
          session.sourceChannel,
          now.toIso8601String(),
          now.toIso8601String(),
          expiresAt.toIso8601String(),
        ],
      );
      await _insertTurn(tx, turn, context.userId, session.sourceChannel);
    });

    return session;
  }

  Future<LocalCaptureCommitResult> captureCommit(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = _readRequiredString(input, 'capture_id');
    await syncService.ensureInitialized();
    final session = await _getActiveSession(captureId, context.effectiveNow);
    if (session == null) {
      throw StateError('Capture session not found or expired: $captureId');
    }
    if (session.sessionStatus == 'committed') {
      throw StateError('Capture session already committed: $captureId');
    }

    final selectedIndexes = _selectedIndexes(input, session.actions.length);
    final created = <LocalCoreEntityRef>[];
    final failed = <LocalCoreEntityRef>[];

    for (final index in selectedIndexes) {
      if (index < 0 || index >= session.actions.length) {
        failed.add(LocalCoreEntityRef(type: 'capture_action', id: '$index'));
        continue;
      }
      final action = session.actions[index];
      try {
        final payload = {...action.payload, 'source_capture_id': captureId};
        if (action.type == 'memo_create') {
          final memo = await memoStore.createMemo(payload, context);
          created.add(LocalCoreEntityRef(type: 'memo', id: memo.id));
        } else if (action.type == 'task_create') {
          final task = await taskStore.createTask(payload, context);
          created.add(LocalCoreEntityRef(type: 'task', id: task.id));
        } else if (action.type == 'expense_create') {
          final tx = await expenseStore.createExpense(payload, context);
          created.add(
            LocalCoreEntityRef(type: 'ledger_transaction', id: tx.id),
          );
        } else {
          failed.add(LocalCoreEntityRef(type: action.type, id: '$index'));
        }
      } catch (_) {
        failed.add(LocalCoreEntityRef(type: action.type, id: '$index'));
      }
    }

    final now = context.effectiveNow.toUtc();
    final undoToken = policy.nextEntityId('undo');
    final turn = LocalCaptureTurn(
      id: policy.nextEntityId('capture_turn'),
      captureId: captureId,
      turnIndex: session.turns.length,
      role: 'system',
      text: 'commit',
      actions: const [],
      selectedActionIndexes: selectedIndexes,
      resultEntities: created,
      turnStatus: failed.isEmpty ? 'committed' : 'partial',
      createdAt: now,
      updatedAt: now,
    );

    await syncService.db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE mcp_capture_sessions SET session_status = ?, updated_at = ?, committed_at = ? '
        'WHERE capture_id = ?',
        [
          created.isEmpty ? 'failed' : 'committed',
          now.toIso8601String(),
          created.isEmpty ? null : now.toIso8601String(),
          captureId,
        ],
      );
      await _insertTurn(tx, turn, context.userId, session.sourceChannel);
      for (final entity in created) {
        await tx.execute(
          'INSERT INTO mcp_undo_actions('
          'id, user_id, undo_token, entity_type, entity_id, action, status, expires_at, created_at'
          ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            policy.nextEntityId('undo_action'),
            context.userId,
            undoToken,
            entity.type,
            entity.id,
            'create',
            'pending',
            now.add(const Duration(hours: 24)).toIso8601String(),
            now.toIso8601String(),
          ],
        );
      }
    });

    return LocalCaptureCommitResult(
      committed: created.isNotEmpty && failed.isEmpty,
      createdEntities: created,
      undoToken: undoToken,
      failedEntities: failed,
    );
  }

  Future<LocalCaptureUndoResult> captureUndo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final undoToken = _readRequiredString(input, 'undo_token');
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT id, entity_type, entity_id FROM mcp_undo_actions '
      'WHERE undo_token = ? AND user_id = ? AND status = ? '
      'ORDER BY created_at ASC',
      [undoToken, context.userId, 'pending'],
    );
    if (rows.isEmpty) {
      throw StateError('Undo token not found or already used: $undoToken');
    }

    var undone = 0;
    String? captureId;
    final entities = <LocalCoreEntityRef>[];
    final failed = <LocalCoreEntityRef>[];
    for (final row in rows) {
      final entity = LocalCoreEntityRef(
        type: row['entity_type'] as String? ?? 'unknown',
        id: row['entity_id'] as String? ?? '',
      );
      try {
        if (entity.type == 'memo') {
          await memoStore.deleteMemo({
            'memo_id': entity.id,
            'status': 'ai_trashed',
          }, context);
        } else if (entity.type == 'task') {
          await taskStore.deleteTask({
            'task_id': entity.id,
            'status': 'ai_trashed',
          }, context);
        } else if (entity.type == 'ledger_transaction') {
          await expenseStore.deleteExpense({
            'transaction_id': entity.id,
            'status': 'ai_trashed',
          }, context);
        } else {
          failed.add(entity);
          continue;
        }
        undone += 1;
        entities.add(entity);
        captureId ??= await _captureIdForEntity(entity);
      } catch (_) {
        failed.add(entity);
      }
    }

    final now = context.effectiveNow.toUtc();
    await syncService.db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE mcp_undo_actions SET status = ?, used_at = ? '
        'WHERE undo_token = ? AND user_id = ? AND status = ?',
        ['used', now.toIso8601String(), undoToken, context.userId, 'pending'],
      );
      final resolvedCaptureId = captureId;
      if (resolvedCaptureId != null) {
        final turn = LocalCaptureTurn(
          id: policy.nextEntityId('capture_turn'),
          captureId: resolvedCaptureId,
          turnIndex: await _nextTurnIndex(resolvedCaptureId),
          role: 'system',
          text: 'undo',
          actions: const [],
          selectedActionIndexes: const [],
          resultEntities: entities,
          turnStatus: failed.isEmpty ? 'undone' : 'partial_undo',
          createdAt: now,
          updatedAt: now,
        );
        await _insertTurn(tx, turn, context.userId, context.sourceChannelName);
      }
    });

    return LocalCaptureUndoResult(
      undone: undone,
      entities: entities,
      failedEntities: failed,
    );
  }

  Future<LocalCaptureSession?> _getActiveSession(
    String captureId,
    DateTime now,
  ) async {
    final row = await syncService.db.getOptional(
      'SELECT capture_id, original_text, timezone, locale, actions, requires_confirmation, '
      'session_status, source_channel, created_at, updated_at, expires_at '
      'FROM mcp_capture_sessions WHERE capture_id = ?',
      [captureId],
    );
    if (row == null) return null;
    final expiresAt = _readDateTimeOrNull(row['expires_at']);
    if (expiresAt != null && expiresAt.isBefore(now.toUtc())) return null;
    final turns = await _turnsFor(captureId);
    return LocalCaptureSession(
      captureId: row['capture_id'] as String,
      originalText: row['original_text'] as String? ?? '',
      timezone: row['timezone'] as String? ?? 'Asia/Shanghai',
      locale: row['locale'] as String? ?? 'zh-CN',
      actions: _decodeActions(row['actions'] as String?),
      requiresConfirmation: (row['requires_confirmation'] as int? ?? 1) == 1,
      sessionStatus: row['session_status'] as String? ?? 'parsed',
      sourceChannel: row['source_channel'] as String? ?? 'local',
      createdAt: _readDateTimeOrNull(row['created_at']),
      updatedAt: _readDateTimeOrNull(row['updated_at']),
      expiresAt: expiresAt,
      turns: turns,
    );
  }

  Future<List<LocalCaptureTurn>> _turnsFor(String captureId) async {
    final rows = await syncService.db.getAll(
      'SELECT id, capture_id, turn_index, role, text, actions, selected_action_indexes, '
      'result_entities, turn_status, created_at, updated_at '
      'FROM mcp_capture_turns WHERE capture_id = ? ORDER BY turn_index ASC',
      [captureId],
    );
    return rows.map(_turnFromRow).toList(growable: false);
  }

  Future<int> _nextTurnIndex(String captureId) async {
    final row = await syncService.db.getOptional(
      'SELECT max(turn_index) AS max_index FROM mcp_capture_turns WHERE capture_id = ?',
      [captureId],
    );
    return (row?['max_index'] as int? ?? -1) + 1;
  }

  Future<String?> _captureIdForEntity(LocalCoreEntityRef entity) async {
    final table = switch (entity.type) {
      'memo' => 'memos',
      'task' => 'tasks',
      'ledger_transaction' => 'ledger_transactions',
      _ => null,
    };
    if (table == null) return null;
    final row = await syncService.db.getOptional(
      'SELECT source_capture_id FROM $table WHERE id = ?',
      [entity.id],
    );
    return row?['source_capture_id'] as String?;
  }

  Future<void> _insertTurn(
    dynamic tx,
    LocalCaptureTurn turn,
    String userId,
    String sourceChannel,
  ) async {
    await tx.execute(
      'INSERT INTO mcp_capture_turns('
      'id, user_id, capture_id, turn_index, role, text, actions, selected_action_indexes, '
      'result_entities, turn_status, source_channel, created_at, updated_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        turn.id,
        userId,
        turn.captureId,
        turn.turnIndex,
        turn.role,
        turn.text,
        _encodeActions(turn.actions),
        jsonEncode(turn.selectedActionIndexes),
        _encodeEntityRefs(turn.resultEntities),
        turn.turnStatus,
        sourceChannel,
        turn.createdAt.toIso8601String(),
        turn.updatedAt.toIso8601String(),
      ],
    );
  }

  LocalCaptureTurn _turnFromRow(Map<String, Object?> row) {
    return LocalCaptureTurn(
      id: row['id'] as String,
      captureId: row['capture_id'] as String,
      turnIndex: row['turn_index'] as int? ?? 0,
      role: row['role'] as String? ?? 'assistant',
      text: row['text'] as String?,
      actions: _decodeActions(row['actions'] as String?),
      selectedActionIndexes: _decodeIntList(
        row['selected_action_indexes'] as String?,
      ),
      resultEntities: _decodeEntityRefs(row['result_entities'] as String?),
      turnStatus: row['turn_status'] as String? ?? 'parsed',
      createdAt: _readRequiredDateTime(row['created_at']),
      updatedAt: _readRequiredDateTime(row['updated_at']),
    );
  }

  List<int> _selectedIndexes(Map<String, Object?> input, int length) {
    final raw = input['selected_action_indexes'];
    if (raw == null) return List<int>.generate(length, (index) => index);
    if (raw is! List) return const [];
    final seen = <int>{};
    return raw.whereType<int>().where(seen.add).toList(growable: false);
  }

  static String _readRequiredString(Map<String, Object?> input, String key) {
    final value = _readOptionalString(input, key);
    if (value == null) throw ArgumentError('$key is required');
    return value;
  }

  static String? _readOptionalString(Map<String, Object?> input, String key) {
    final value = input[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _readStringList(Map<String, Object?> input, String key) {
    final value = input[key];
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }

  static String _encodeActions(List<LocalCaptureAction> actions) {
    return jsonEncode(
      actions
          .map(
            (action) => {
              'type': action.type,
              'payload': action.payload,
              'confidence': action.confidence,
              'raw_text': action.rawText,
            },
          )
          .toList(),
    );
  }

  static List<LocalCaptureAction> _decodeActions(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) {
          final json = item.cast<String, Object?>();
          return LocalCaptureAction(
            type: json['type'] as String? ?? 'memo_create',
            payload:
                (json['payload'] as Map?)?.cast<String, Object?>() ?? const {},
            confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
            rawText: json['raw_text'] as String?,
          );
        })
        .toList(growable: false);
  }

  static String _encodeEntityRefs(List<LocalCoreEntityRef> refs) {
    return jsonEncode(
      refs.map((item) => {'type': item.type, 'id': item.id}).toList(),
    );
  }

  static List<LocalCoreEntityRef> _decodeEntityRefs(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) {
          final json = item.cast<String, Object?>();
          return LocalCoreEntityRef(
            type: json['type'] as String? ?? 'unknown',
            id: json['id'] as String? ?? '',
          );
        })
        .toList(growable: false);
  }

  static List<int> _decodeIntList(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded.whereType<int>().toList(growable: false);
  }

  static DateTime _readRequiredDateTime(Object? value) {
    final parsed = _readDateTimeOrNull(value);
    if (parsed == null) {
      throw ArgumentError('Expected ISO datetime string, got $value');
    }
    return parsed;
  }

  static DateTime? _readDateTimeOrNull(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.parse(value).toUtc();
    }
    return null;
  }
}
