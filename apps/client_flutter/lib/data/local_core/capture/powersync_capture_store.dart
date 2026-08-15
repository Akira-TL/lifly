import 'dart:convert';

import 'package:client_flutter/data/local_core/capture/local_capture_asset_context_resolver.dart';
import 'package:client_flutter/data/local_core/ledger/powersync_expense_store.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/memo/powersync_memo_store.dart';
import 'package:client_flutter/data/local_core/task/powersync_task_store.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter/foundation.dart';

part 'powersync_capture_helpers.dart';

String _captureCommitCauseType(Object error) {
  final cause = error is LocalCoreWriteException ? error.cause : error;
  return cause.runtimeType.toString();
}

String _captureCommitErrorClass(Object error) {
  final cause = error is LocalCoreWriteException ? error.cause : error;
  final message = cause.toString().toLowerCase();
  if (message.contains('transaction') ||
      message.contains('locked') ||
      message.contains('busy')) {
    return 'sqlite_write';
  }
  if (message.contains('encrypted') ||
      message.contains('revision') ||
      message.contains('account e2ee')) {
    return 'e2ee';
  }
  if (cause is FormatException || cause is ArgumentError) return 'validation';
  if (cause is StateError) return 'state';
  if (error is LocalCoreWriteException) return 'local_core_write';
  return 'unknown';
}

class PowerSyncCaptureStore {
  final SyncService syncService;
  final PowerSyncMemoStore memoStore;
  final PowerSyncTaskStore taskStore;
  final PowerSyncExpenseStore expenseStore;
  final LocalCaptureAssetContextResolver assetContextResolver;
  final LocalCoreWritePolicy policy;

  PowerSyncCaptureStore({
    required this.syncService,
    required this.memoStore,
    required this.taskStore,
    required this.expenseStore,
    LocalCaptureAssetContextResolver? assetContextResolver,
    LocalCoreWritePolicy? policy,
  }) : assetContextResolver =
           assetContextResolver ??
           LocalCaptureAssetContextResolver(syncService),
       policy = policy ?? LocalCoreWritePolicy();

  Future<List<LocalCaptureAssetContext>> listCaptureAssets(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return assetContextResolver.listAvailable(
      userId: context.userId,
      limit: input['limit'] as int? ?? 50,
    );
  }

  Future<LocalCaptureSession> captureParse(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final text = _readRequiredString(input, 'text');
    final timezone = _readOptionalString(input, 'timezone') ?? 'Asia/Shanghai';
    final locale = _readOptionalString(input, 'locale') ?? 'zh-CN';
    final assetIds = _readStringList(input, 'asset_ids');
    final assetContext = await assetContextResolver.resolve(
      assetIds,
      userId: context.userId,
    );
    final now = context.effectiveNow.toUtc();
    final captureId = policy.nextEntityId('capture');
    final expiresAt = now.add(const Duration(days: 30));
    final actions = _parseLocalActions(
      text: text,
      captureId: captureId,
      assetIds: assetIds,
      now: now,
    );
    final userTurn = LocalCaptureTurn(
      id: policy.nextEntityId('capture_turn'),
      captureId: captureId,
      turnIndex: 0,
      role: 'user',
      text: text,
      assetIds: assetIds,
      assetContext: assetContext,
      actions: const [],
      selectedActionIndexes: const [],
      resultEntities: const [],
      turnStatus: 'accepted',
      createdAt: now,
      updatedAt: now,
    );
    final actionTurn = LocalCaptureTurn(
      id: policy.nextEntityId('capture_turn'),
      captureId: captureId,
      turnIndex: 1,
      role: 'assistant',
      text: null,
      assetIds: assetIds,
      assetContext: assetContext,
      actions: actions,
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
      actions: actions,
      requiresConfirmation: true,
      committed: false,
      sessionStatus: 'active',
      sourceChannel: context.sourceChannelName,
      createdAt: now,
      updatedAt: now,
      expiresAt: expiresAt,
      turns: [userTurn, actionTurn],
    );

    await syncService.ensureInitialized();
    await syncService.db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO mcp_capture_sessions('
        'id, capture_id, user_id, original_text, timezone, locale, actions, requires_confirmation, '
        'committed, session_status, source_channel, created_at, updated_at, expires_at, revision'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          session.captureId,
          session.captureId,
          context.userId,
          session.originalText,
          session.timezone,
          session.locale,
          _encodeActions(session.actions),
          session.requiresConfirmation ? 1 : 0,
          session.committed ? 1 : 0,
          session.sessionStatus,
          session.sourceChannel,
          now.toIso8601String(),
          now.toIso8601String(),
          expiresAt.toIso8601String(),
          1,
        ],
      );
      await _insertTurn(tx, userTurn, context.userId, session.sourceChannel);
      await _insertTurn(tx, actionTurn, context.userId, session.sourceChannel);
    });
    await syncService.flushLocalMutations();

    return session;
  }

  Future<List<LocalCaptureSession>> listCaptureSessions(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    await syncService.ensureInitialized();
    final status = _readOptionalString(input, 'status') ?? 'active';
    final limit = (input['limit'] as int? ?? 20).clamp(1, 100);
    final offset = (input['offset'] as int? ?? 0).clamp(0, 1000000);
    final conditions = <String>['user_id = ?'];
    final parameters = <Object?>[context.userId];
    if (status == 'active') {
      conditions.add(
        "session_status IN ('active', 'parsed', 'committed', 'failed')",
      );
    } else if (status != 'all') {
      conditions.add('session_status = ?');
      parameters.add(status);
    }
    parameters.addAll([limit, offset]);
    final rows = await syncService.db.getAll(
      'SELECT capture_id, original_text, timezone, locale, actions, requires_confirmation, '
      'committed, session_status, source_channel, created_at, updated_at, expires_at, '
      'committed_at, dismissed_at FROM mcp_capture_sessions '
      'WHERE ${conditions.join(' AND ')} ORDER BY updated_at DESC LIMIT ? OFFSET ?',
      parameters,
    );
    final sessions = <LocalCaptureSession>[];
    for (final row in rows) {
      sessions.add(await _sessionFromRow(row, includeTurns: false));
    }
    return sessions;
  }

  Future<LocalCaptureSession?> getCaptureSession(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = _readRequiredString(input, 'capture_id');
    await syncService.ensureInitialized();
    return _getSession(captureId, context.userId, includeTurns: true);
  }

  Future<LocalCaptureSession> appendCaptureTurn(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = _readRequiredString(input, 'capture_id');
    final text = _readRequiredString(input, 'text');
    final assetIds = _readStringList(input, 'asset_ids');
    final assetContext = await assetContextResolver.resolve(
      assetIds,
      userId: context.userId,
    );
    await syncService.ensureInitialized();
    final session = await _getActiveSession(
      captureId,
      context.effectiveNow,
      context.userId,
    );
    if (session == null) {
      throw StateError(
        'Capture session not found, dismissed, or expired: $captureId',
      );
    }
    final now = context.effectiveNow.toUtc();
    final firstIndex = await _nextTurnIndex(captureId);
    final actions = _parseLocalActions(
      text: text,
      captureId: captureId,
      assetIds: assetIds,
      now: now,
    );
    final userTurn = LocalCaptureTurn(
      id: policy.nextEntityId('capture_turn'),
      captureId: captureId,
      turnIndex: firstIndex,
      role: 'user',
      text: text,
      assetIds: assetIds,
      assetContext: assetContext,
      actions: const [],
      selectedActionIndexes: const [],
      resultEntities: const [],
      turnStatus: 'accepted',
      createdAt: now,
      updatedAt: now,
    );
    final actionTurn = LocalCaptureTurn(
      id: policy.nextEntityId('capture_turn'),
      captureId: captureId,
      turnIndex: firstIndex + 1,
      role: 'assistant',
      text: null,
      assetIds: assetIds,
      assetContext: assetContext,
      actions: actions,
      selectedActionIndexes: const [],
      resultEntities: const [],
      turnStatus: 'parsed',
      createdAt: now,
      updatedAt: now,
    );
    final expiresAt = now.add(const Duration(days: 30));
    await syncService.db.writeTransaction((tx) async {
      await _insertTurn(tx, userTurn, context.userId, session.sourceChannel);
      await _insertTurn(tx, actionTurn, context.userId, session.sourceChannel);
      await tx.execute(
        'UPDATE mcp_capture_sessions SET actions = ?, requires_confirmation = ?, '
        'session_status = ?, updated_at = ?, expires_at = ?, revision = revision + 1 '
        'WHERE capture_id = ? AND user_id = ?',
        [
          _encodeActions(actions),
          1,
          'active',
          now.toIso8601String(),
          expiresAt.toIso8601String(),
          captureId,
          context.userId,
        ],
      );
    });
    await syncService.flushLocalMutations();
    return (await _getSession(captureId, context.userId, includeTurns: true))!;
  }

  Future<LocalCaptureTurn> reviseCaptureAction(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = _readRequiredString(input, 'capture_id');
    final turnId = _readRequiredString(input, 'turn_id');
    final actionIndex = input['action_index'] as int?;
    if (actionIndex == null || actionIndex < 0) {
      throw ArgumentError('action_index must be non-negative');
    }
    final rawPayload = input['payload'];
    if (rawPayload is! Map) throw ArgumentError('payload is required');
    await syncService.ensureInitialized();
    final session = await _getActiveSession(
      captureId,
      context.effectiveNow,
      context.userId,
    );
    if (session == null) {
      throw StateError(
        'Capture session not found, dismissed, or expired: $captureId',
      );
    }
    final row = await syncService.db.getOptional(
      'SELECT id, capture_id, turn_index, role, text, asset_ids, asset_context, actions, '
      'selected_action_indexes, result_entities, undo_token, supersedes_turn_id, '
      'turn_status, created_at, updated_at FROM mcp_capture_turns '
      'WHERE id = ? AND capture_id = ? AND user_id = ?',
      [turnId, captureId, context.userId],
    );
    if (row == null) throw StateError('Capture action turn not found: $turnId');
    final sourceTurn = _turnFromRow(row);
    if (sourceTurn.role != 'assistant') {
      throw StateError('Only assistant action turns can be revised');
    }
    if (const {'committed', 'partial'}.contains(sourceTurn.turnStatus)) {
      throw StateError('Undo the committed turn before revising it');
    }
    if (actionIndex >= sourceTurn.actions.length) {
      throw RangeError.index(actionIndex, sourceTurn.actions, 'action_index');
    }
    final sourceAction = sourceTurn.actions[actionIndex];
    final revisedActions = [...sourceTurn.actions];
    revisedActions[actionIndex] = LocalCaptureAction(
      type: _readOptionalString(input, 'action_type') ?? sourceAction.type,
      payload: rawPayload.cast<String, Object?>(),
      confidence:
          (input['confidence'] as num?)?.toDouble() ?? sourceAction.confidence,
      rawText: sourceAction.rawText,
    );
    final now = context.effectiveNow.toUtc();
    final revisedTurn = LocalCaptureTurn(
      id: policy.nextEntityId('capture_turn'),
      captureId: captureId,
      turnIndex: await _nextTurnIndex(captureId),
      role: 'assistant',
      text: _readOptionalString(input, 'note'),
      assetIds: sourceTurn.assetIds,
      assetContext: sourceTurn.assetContext,
      actions: revisedActions,
      selectedActionIndexes: const [],
      resultEntities: const [],
      supersedesTurnId: sourceTurn.id,
      turnStatus: 'revised',
      createdAt: now,
      updatedAt: now,
    );
    await syncService.db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE mcp_capture_turns SET turn_status = ?, updated_at = ?, '
        'revision = revision + 1 WHERE id = ?',
        ['superseded', now.toIso8601String(), sourceTurn.id],
      );
      await _insertTurn(tx, revisedTurn, context.userId, session.sourceChannel);
      await tx.execute(
        'UPDATE mcp_capture_sessions SET actions = ?, requires_confirmation = ?, '
        'session_status = ?, updated_at = ?, revision = revision + 1 '
        'WHERE capture_id = ? AND user_id = ?',
        [
          _encodeActions(revisedActions),
          1,
          'active',
          now.toIso8601String(),
          captureId,
          context.userId,
        ],
      );
    });
    await syncService.flushLocalMutations();
    return revisedTurn;
  }

  Future<LocalCaptureSession> dismissCaptureSession(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = _readRequiredString(input, 'capture_id');
    await syncService.ensureInitialized();
    final session = await _getSession(
      captureId,
      context.userId,
      includeTurns: true,
    );
    if (session == null) {
      throw StateError('Capture session not found: $captureId');
    }
    if (session.sessionStatus != 'dismissed') {
      final now = context.effectiveNow.toUtc();
      final turn = LocalCaptureTurn(
        id: policy.nextEntityId('capture_turn'),
        captureId: captureId,
        turnIndex: await _nextTurnIndex(captureId),
        role: 'system',
        text: _readOptionalString(input, 'reason') ?? 'dismiss',
        actions: const [],
        selectedActionIndexes: const [],
        resultEntities: const [],
        turnStatus: 'dismissed',
        createdAt: now,
        updatedAt: now,
      );
      await syncService.db.writeTransaction((tx) async {
        await _insertTurn(tx, turn, context.userId, session.sourceChannel);
        await tx.execute(
          'UPDATE mcp_capture_sessions SET session_status = ?, dismissed_at = ?, updated_at = ?, '
          'revision = revision + 1 WHERE capture_id = ? AND user_id = ?',
          [
            'dismissed',
            now.toIso8601String(),
            now.toIso8601String(),
            captureId,
            context.userId,
          ],
        );
      });
      await syncService.flushLocalMutations();
    }
    return (await _getSession(captureId, context.userId, includeTurns: true))!;
  }

  Future<LocalCaptureCommitResult> captureCommit(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = _readRequiredString(input, 'capture_id');
    await syncService.ensureInitialized();
    final session = await _getActiveSession(
      captureId,
      context.effectiveNow,
      context.userId,
    );
    if (session == null) {
      throw StateError(
        'Capture session not found, dismissed, or expired: $captureId',
      );
    }
    final requestedTurnId = _readOptionalString(input, 'turn_id');
    final actionTurn = requestedTurnId == null
        ? await _latestActionTurn(captureId, context.userId)
        : await _captureTurnById(captureId, requestedTurnId, context.userId);
    if (actionTurn == null || actionTurn.role != 'assistant') {
      throw StateError('Capture action turn not found');
    }
    if (const {'committed', 'partial'}.contains(actionTurn.turnStatus)) {
      throw StateError('Capture turn already committed: ${actionTurn.id}');
    }

    final selectedIndexes = _selectedIndexes(input, actionTurn.actions.length);
    final created = <LocalCoreEntityRef>[];
    final failed = <LocalCoreEntityRef>[];

    for (final index in selectedIndexes) {
      if (index < 0 || index >= actionTurn.actions.length) {
        failed.add(LocalCoreEntityRef(type: 'capture_action', id: '$index'));
        continue;
      }
      final action = actionTurn.actions[index];
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
      } catch (error) {
        debugPrint(
          '[LIFLY_LOCAL_CORE][capture_commit_failed] '
          'action_type=${action.type} error_class=${_captureCommitErrorClass(error)} '
          'cause_type=${_captureCommitCauseType(error)}',
        );
        failed.add(LocalCoreEntityRef(type: action.type, id: '$index'));
      }
    }

    final now = context.effectiveNow.toUtc();
    final undoToken = created.isEmpty ? '' : policy.nextEntityId('undo');
    final turnStatus = created.isEmpty
        ? 'failed'
        : failed.isEmpty
        ? 'committed'
        : 'partial';
    await syncService.db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE mcp_capture_sessions SET committed = ?, session_status = ?, '
        'updated_at = ?, committed_at = ?, revision = revision + 1 '
        'WHERE capture_id = ? AND user_id = ?',
        [
          created.isEmpty ? (session.committed ? 1 : 0) : 1,
          'active',
          now.toIso8601String(),
          created.isEmpty
              ? session.committedAt?.toIso8601String()
              : now.toIso8601String(),
          captureId,
          context.userId,
        ],
      );
      await tx.execute(
        'UPDATE mcp_capture_turns SET selected_action_indexes = ?, result_entities = ?, '
        'undo_token = ?, turn_status = ?, updated_at = ?, revision = revision + 1 '
        'WHERE id = ? AND user_id = ?',
        [
          jsonEncode(selectedIndexes),
          _encodeEntityRefs(created),
          undoToken.isEmpty ? null : undoToken,
          turnStatus,
          now.toIso8601String(),
          actionTurn.id,
          context.userId,
        ],
      );
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
    await syncService.flushLocalMutations();

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
    final committedTurn = await syncService.db.getOptional(
      'SELECT id, capture_id FROM mcp_capture_turns WHERE undo_token = ? AND user_id = ?',
      [undoToken, context.userId],
    );
    String? captureId = committedTurn?['capture_id'] as String?;
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
      final committedTurnId = committedTurn?['id'] as String?;
      if (committedTurnId != null) {
        await tx.execute(
          'UPDATE mcp_capture_turns SET turn_status = ?, updated_at = ?, '
          'revision = revision + 1 WHERE id = ?',
          ['undone', now.toIso8601String(), committedTurnId],
        );
      }
      final resolvedCaptureId = captureId;
      if (resolvedCaptureId != null) {
        final turn = LocalCaptureTurn(
          id: policy.nextEntityId('capture_turn'),
          captureId: resolvedCaptureId,
          turnIndex: await _nextTurnIndexWithHandle(tx, resolvedCaptureId),
          role: 'system',
          text: 'undo',
          actions: const [],
          selectedActionIndexes: const [],
          resultEntities: entities,
          undoToken: undoToken,
          turnStatus: failed.isEmpty ? 'undone' : 'partial_undo',
          createdAt: now,
          updatedAt: now,
        );
        await _insertTurn(tx, turn, context.userId, context.sourceChannelName);
      }
    });
    await syncService.flushLocalMutations();

    return LocalCaptureUndoResult(
      undone: undone,
      entities: entities,
      failedEntities: failed,
    );
  }

  Future<LocalCaptureSession?> _getActiveSession(
    String captureId,
    DateTime now,
    String userId,
  ) async {
    final session = await _getSession(captureId, userId, includeTurns: true);
    if (session == null || session.sessionStatus == 'dismissed') return null;
    final expiresAt = session.expiresAt;
    if (expiresAt != null && expiresAt.isBefore(now.toUtc())) return null;
    return session;
  }

  Future<LocalCaptureSession?> _getSession(
    String captureId,
    String userId, {
    required bool includeTurns,
  }) async {
    final row = await syncService.db.getOptional(
      'SELECT capture_id, original_text, timezone, locale, actions, requires_confirmation, '
      'committed, session_status, source_channel, created_at, updated_at, expires_at, '
      'committed_at, dismissed_at FROM mcp_capture_sessions '
      'WHERE capture_id = ? AND user_id = ?',
      [captureId, userId],
    );
    if (row == null) return null;
    return _sessionFromRow(row, includeTurns: includeTurns);
  }

  Future<LocalCaptureSession> _sessionFromRow(
    Map<String, Object?> row, {
    required bool includeTurns,
  }) async {
    final captureId = row['capture_id'] as String;
    return LocalCaptureSession(
      captureId: captureId,
      originalText: row['original_text'] as String? ?? '',
      timezone: row['timezone'] as String? ?? 'Asia/Shanghai',
      locale: row['locale'] as String? ?? 'zh-CN',
      actions: _decodeActions(row['actions'] as String?),
      requiresConfirmation: (row['requires_confirmation'] as int? ?? 1) == 1,
      committed: (row['committed'] as int? ?? 0) == 1,
      sessionStatus: row['session_status'] as String? ?? 'active',
      sourceChannel: row['source_channel'] as String? ?? 'local',
      createdAt: _readDateTimeOrNull(row['created_at']),
      updatedAt: _readDateTimeOrNull(row['updated_at']),
      expiresAt: _readDateTimeOrNull(row['expires_at']),
      committedAt: _readDateTimeOrNull(row['committed_at']),
      dismissedAt: _readDateTimeOrNull(row['dismissed_at']),
      turns: includeTurns ? await _turnsFor(captureId) : const [],
    );
  }

  Future<List<LocalCaptureTurn>> _turnsFor(String captureId) async {
    final rows = await syncService.db.getAll(
      'SELECT id, capture_id, turn_index, role, text, asset_ids, asset_context, actions, '
      'selected_action_indexes, result_entities, undo_token, supersedes_turn_id, '
      'turn_status, created_at, updated_at FROM mcp_capture_turns '
      'WHERE capture_id = ? ORDER BY turn_index ASC, created_at ASC',
      [captureId],
    );
    return rows.map(_turnFromRow).toList(growable: false);
  }

  Future<LocalCaptureTurn?> _captureTurnById(
    String captureId,
    String turnId,
    String userId,
  ) async {
    final row = await syncService.db.getOptional(
      'SELECT id, capture_id, turn_index, role, text, asset_ids, asset_context, actions, '
      'selected_action_indexes, result_entities, undo_token, supersedes_turn_id, '
      'turn_status, created_at, updated_at FROM mcp_capture_turns '
      'WHERE id = ? AND capture_id = ? AND user_id = ?',
      [turnId, captureId, userId],
    );
    return row == null ? null : _turnFromRow(row);
  }

  Future<LocalCaptureTurn?> _latestActionTurn(
    String captureId,
    String userId,
  ) async {
    final row = await syncService.db.getOptional(
      'SELECT id, capture_id, turn_index, role, text, asset_ids, asset_context, actions, '
      'selected_action_indexes, result_entities, undo_token, supersedes_turn_id, '
      'turn_status, created_at, updated_at FROM mcp_capture_turns '
      "WHERE capture_id = ? AND user_id = ? AND role = 'assistant' "
      "AND turn_status IN ('parsed', 'revised', 'failed') "
      'ORDER BY turn_index DESC, created_at DESC LIMIT 1',
      [captureId, userId],
    );
    return row == null ? null : _turnFromRow(row);
  }

  Future<int> _nextTurnIndex(String captureId) =>
      _nextTurnIndexWithHandle(syncService.db, captureId);

  Future<int> _nextTurnIndexWithHandle(dynamic handle, String captureId) async {
    final row = await handle.getOptional(
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
      'id, user_id, capture_id, turn_index, role, text, asset_ids, asset_context, actions, '
      'selected_action_indexes, result_entities, undo_token, supersedes_turn_id, '
      'turn_status, source_channel, created_at, updated_at, revision'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        turn.id,
        userId,
        turn.captureId,
        turn.turnIndex,
        turn.role,
        turn.text,
        jsonEncode(turn.assetIds),
        _encodeAssetContext(turn.assetContext),
        _encodeActions(turn.actions),
        jsonEncode(turn.selectedActionIndexes),
        _encodeEntityRefs(turn.resultEntities),
        turn.undoToken,
        turn.supersedesTurnId,
        turn.turnStatus,
        sourceChannel,
        turn.createdAt.toIso8601String(),
        turn.updatedAt.toIso8601String(),
        1,
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
      assetIds: _decodeStringList(row['asset_ids'] as String?),
      assetContext: _decodeAssetContext(row['asset_context'] as String?),
      actions: _decodeActions(row['actions'] as String?),
      selectedActionIndexes: _decodeIntList(
        row['selected_action_indexes'] as String?,
      ),
      resultEntities: _decodeEntityRefs(row['result_entities'] as String?),
      undoToken: row['undo_token'] as String?,
      supersedesTurnId: row['supersedes_turn_id'] as String?,
      turnStatus: row['turn_status'] as String? ?? 'parsed',
      createdAt: _readRequiredDateTime(row['created_at']),
      updatedAt: _readRequiredDateTime(row['updated_at']),
    );
  }
}
