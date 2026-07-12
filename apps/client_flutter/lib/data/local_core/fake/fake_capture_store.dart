part of '../fake_local_core_bridge.dart';

mixin _FakeCaptureStore on _FakeLocalCoreState {
  @override
  Future<LocalAssetRecord> registerExternalAsset(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final now = context.effectiveNow;
    final asset = LocalAssetRecord(
      id: _nextStableId('asset'),
      kind: 'external',
      assetType: input['asset_type'] as String? ?? 'link',
      title: input['title'] as String?,
      externalUrl: input['external_url'] as String?,
      syncStatus: 'synced',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    _assets.insert(0, asset);
    return asset;
  }

  @override
  Future<List<LocalCaptureAssetContext>> listCaptureAssets(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final limit = input['limit'] as int? ?? 50;
    return _assets.take(limit).map(_fakeAssetContext).toList(growable: false);
  }

  @override
  Future<LocalCaptureSession> captureParse(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final text = input['text'] as String? ?? '';
    final assetIds = (input['asset_ids'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final assetContext = _fakeAssetContexts(assetIds);
    final now = context.effectiveNow;
    final captureId = _nextStableId('capture');
    final action = LocalCaptureAction(
      type: 'memo_create',
      payload: {
        'type': 'memo',
        'title': null,
        'content_markdown': text,
        'tags': ['capture'],
        if (assetIds.isNotEmpty) 'asset_ids': assetIds,
      },
      confidence: 0.8,
      rawText: text,
    );
    final userTurn = LocalCaptureTurn(
      id: _nextStableId('capture_turn'),
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
      id: _nextStableId('capture_turn'),
      captureId: captureId,
      turnIndex: 1,
      role: 'assistant',
      text: null,
      assetIds: assetIds,
      assetContext: assetContext,
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
      timezone: input['timezone'] as String? ?? 'Asia/Shanghai',
      locale: input['locale'] as String? ?? 'zh-CN',
      actions: [action],
      requiresConfirmation: true,
      sessionStatus: 'active',
      sourceChannel: context.sourceChannelName,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.add(const Duration(days: 30)),
      turns: [userTurn, actionTurn],
    );
    _captures[session.captureId] = session;
    return session;
  }

  @override
  Future<List<LocalCaptureSession>> listCaptureSessions(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final status = input['status'] as String? ?? 'active';
    final limit = input['limit'] as int? ?? 20;
    final offset = input['offset'] as int? ?? 0;
    final sessions = _captures.values
        .where(
          (item) =>
              status == 'all' ||
              (status == 'active'
                  ? item.sessionStatus != 'dismissed'
                  : item.sessionStatus == status),
        )
        .toList()
      ..sort(
        (left, right) =>
            (right.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  left.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
      );
    return sessions.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<LocalCaptureSession?> getCaptureSession(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    return _captures[input['capture_id'] as String?];
  }

  @override
  Future<LocalCaptureSession> appendCaptureTurn(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = input['capture_id'] as String?;
    final session = _captures[captureId];
    if (session == null || session.sessionStatus == 'dismissed') {
      throw StateError('Capture not found or dismissed: $captureId');
    }
    final text = input['text'] as String? ?? '';
    final assetIds = (input['asset_ids'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final assetContext = _fakeAssetContexts(assetIds);
    final now = context.effectiveNow;
    final action = LocalCaptureAction(
      type: 'memo_create',
      payload: {
        'type': 'memo',
        'title': null,
        'content_markdown': text,
        'tags': ['capture'],
        if (assetIds.isNotEmpty) 'asset_ids': assetIds,
      },
      confidence: 0.8,
      rawText: text,
    );
    final nextIndex = session.turns.length;
    final turns = [
      ...session.turns,
      LocalCaptureTurn(
        id: _nextStableId('capture_turn'),
        captureId: session.captureId,
        turnIndex: nextIndex,
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
      ),
      LocalCaptureTurn(
        id: _nextStableId('capture_turn'),
        captureId: session.captureId,
        turnIndex: nextIndex + 1,
        role: 'assistant',
        text: null,
        assetIds: assetIds,
        assetContext: assetContext,
        actions: [action],
        selectedActionIndexes: const [],
        resultEntities: const [],
        turnStatus: 'parsed',
        createdAt: now,
        updatedAt: now,
      ),
    ];
    final updated = _copyFakeCaptureSession(
      session,
      actions: [action],
      updatedAt: now,
      expiresAt: now.add(const Duration(days: 30)),
      turns: turns,
    );
    _captures[session.captureId] = updated;
    return updated;
  }

  @override
  Future<LocalCaptureTurn> reviseCaptureAction(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = input['capture_id'] as String?;
    final turnId = input['turn_id'] as String?;
    final session = _captures[captureId];
    if (session == null || session.sessionStatus == 'dismissed') {
      throw StateError('Capture not found or dismissed: $captureId');
    }
    final sourceIndex = session.turns.indexWhere((turn) => turn.id == turnId);
    if (sourceIndex < 0) throw StateError('Capture turn not found: $turnId');
    final sourceTurn = session.turns[sourceIndex];
    if (const {'committed', 'partial'}.contains(sourceTurn.turnStatus)) {
      throw StateError('Undo the committed turn before revising it');
    }
    final actionIndex = input['action_index'] as int? ?? -1;
    if (actionIndex < 0 || actionIndex >= sourceTurn.actions.length) {
      throw RangeError.index(actionIndex, sourceTurn.actions, 'action_index');
    }
    final payload = (input['payload'] as Map?)?.cast<String, Object?>();
    if (payload == null) throw ArgumentError('payload is required');
    final oldAction = sourceTurn.actions[actionIndex];
    final actions = [...sourceTurn.actions];
    actions[actionIndex] = LocalCaptureAction(
      type: input['action_type'] as String? ?? oldAction.type,
      payload: payload,
      confidence:
          (input['confidence'] as num?)?.toDouble() ?? oldAction.confidence,
      rawText: oldAction.rawText,
    );
    final now = context.effectiveNow;
    final revisedTurn = LocalCaptureTurn(
      id: _nextStableId('capture_turn'),
      captureId: session.captureId,
      turnIndex: session.turns.length,
      role: 'assistant',
      text: input['note'] as String?,
      assetIds: sourceTurn.assetIds,
      assetContext: sourceTurn.assetContext,
      actions: actions,
      selectedActionIndexes: const [],
      resultEntities: const [],
      supersedesTurnId: sourceTurn.id,
      turnStatus: 'revised',
      createdAt: now,
      updatedAt: now,
    );
    final turns = [...session.turns];
    turns[sourceIndex] = _copyFakeCaptureTurn(
      sourceTurn,
      turnStatus: 'superseded',
      updatedAt: now,
    );
    turns.add(revisedTurn);
    _captures[session.captureId] = _copyFakeCaptureSession(
      session,
      actions: actions,
      updatedAt: now,
      turns: turns,
    );
    return revisedTurn;
  }

  @override
  Future<LocalCaptureSession> dismissCaptureSession(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = input['capture_id'] as String?;
    final session = _captures[captureId];
    if (session == null) throw StateError('Capture not found: $captureId');
    if (session.sessionStatus == 'dismissed') return session;
    final now = context.effectiveNow;
    final dismissed = _copyFakeCaptureSession(
      session,
      sessionStatus: 'dismissed',
      updatedAt: now,
      dismissedAt: now,
      turns: [
        ...session.turns,
        LocalCaptureTurn(
          id: _nextStableId('capture_turn'),
          captureId: session.captureId,
          turnIndex: session.turns.length,
          role: 'system',
          text: input['reason'] as String? ?? 'dismiss',
          actions: const [],
          selectedActionIndexes: const [],
          resultEntities: const [],
          turnStatus: 'dismissed',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    _captures[session.captureId] = dismissed;
    return dismissed;
  }

  @override
  Future<LocalCaptureCommitResult> captureCommit(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = input['capture_id'] as String?;
    final session = _captures[captureId];
    if (session == null || session.sessionStatus == 'dismissed') {
      throw StateError('Capture not found or dismissed: $captureId');
    }
    final requestedTurnId = input['turn_id'] as String?;
    final turnIndex = requestedTurnId == null
        ? session.turns.lastIndexWhere(
            (turn) =>
                turn.role == 'assistant' &&
                const {'parsed', 'revised', 'failed'}.contains(turn.turnStatus),
          )
        : session.turns.indexWhere((turn) => turn.id == requestedTurnId);
    if (turnIndex < 0) throw StateError('Capture action turn not found');
    final actionTurn = session.turns[turnIndex];
    if (const {'committed', 'partial'}.contains(actionTurn.turnStatus)) {
      throw StateError('Capture turn already committed: ${actionTurn.id}');
    }

    final rawIndexes = input['selected_action_indexes'] as List?;
    final indexes = rawIndexes?.whereType<int>().toList() ??
        List<int>.generate(actionTurn.actions.length, (index) => index);
    final created = <LocalCoreEntityRef>[];
    final failed = <LocalCoreEntityRef>[];

    for (final index in indexes) {
      if (index < 0 || index >= actionTurn.actions.length) {
        failed.add(LocalCoreEntityRef(type: 'capture_action', id: '$index'));
        continue;
      }
      final action = actionTurn.actions[index];
      try {
        if (action.type == 'memo_create') {
          final memo = await createMemo(action.payload, context);
          created.add(LocalCoreEntityRef(type: 'memo', id: memo.id));
        } else if (action.type == 'task_create') {
          final task = await createTask(action.payload, context);
          created.add(LocalCoreEntityRef(type: 'task', id: task.id));
        } else if (action.type == 'expense_create') {
          final expense = await createExpense(action.payload, context);
          created.add(
            LocalCoreEntityRef(type: 'ledger_transaction', id: expense.id),
          );
        } else {
          failed.add(LocalCoreEntityRef(type: action.type, id: '$index'));
        }
      } catch (_) {
        failed.add(LocalCoreEntityRef(type: action.type, id: '$index'));
      }
    }

    final undoToken = created.isEmpty ? '' : _nextStableId('undo');
    if (created.isNotEmpty) {
      _undoEntries[undoToken] = created;
      _undoCaptureIds[undoToken] = session.captureId;
    }
    final now = context.effectiveNow;
    final turns = [...session.turns];
    turns[turnIndex] = _copyFakeCaptureTurn(
      actionTurn,
      selectedActionIndexes: indexes,
      resultEntities: created,
      undoToken: undoToken.isEmpty ? null : undoToken,
      turnStatus: created.isEmpty
          ? 'failed'
          : failed.isEmpty
          ? 'committed'
          : 'partial',
      updatedAt: now,
    );
    _captures[session.captureId] = _copyFakeCaptureSession(
      session,
      committed: session.committed || created.isNotEmpty,
      updatedAt: now,
      committedAt: created.isEmpty ? session.committedAt : now,
      turns: turns,
    );
    return LocalCaptureCommitResult(
      committed: created.isNotEmpty && failed.isEmpty,
      createdEntities: created,
      undoToken: undoToken,
      failedEntities: failed,
    );
  }

  @override
  Future<LocalCaptureUndoResult> captureUndo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final undoToken = input['undo_token'] as String?;
    final entries = _undoEntries[undoToken];
    if (entries == null) throw StateError('Undo token not found: $undoToken');

    var undone = 0;
    final entities = <LocalCoreEntityRef>[];
    final failed = <LocalCoreEntityRef>[];
    for (final entry in entries) {
      try {
        if (entry.type == 'memo') {
          await deleteMemo(
            {'memo_id': entry.id, 'status': 'ai_trashed'},
            context,
          );
        } else if (entry.type == 'task') {
          await deleteTask(
            {'task_id': entry.id, 'status': 'ai_trashed'},
            context,
          );
        } else if (entry.type == 'ledger_transaction') {
          await deleteExpense({
            'transaction_id': entry.id,
            'status': 'ai_trashed',
          }, context);
        } else {
          failed.add(entry);
          continue;
        }
        undone += 1;
        entities.add(entry);
      } catch (_) {
        failed.add(entry);
      }
    }

    final captureId = _undoCaptureIds.remove(undoToken);
    _undoEntries.remove(undoToken);
    if (captureId != null && _captures[captureId] != null) {
      final session = _captures[captureId]!;
      final now = context.effectiveNow;
      final turns = session.turns
          .map(
            (turn) => turn.undoToken == undoToken
                ? _copyFakeCaptureTurn(
                    turn,
                    turnStatus: 'undone',
                    updatedAt: now,
                  )
                : turn,
          )
          .toList();
      turns.add(
        LocalCaptureTurn(
          id: _nextStableId('capture_turn'),
          captureId: captureId,
          turnIndex: turns.length,
          role: 'system',
          text: 'undo',
          actions: const [],
          selectedActionIndexes: const [],
          resultEntities: entities,
          undoToken: undoToken,
          turnStatus: failed.isEmpty ? 'undone' : 'partial_undo',
          createdAt: now,
          updatedAt: now,
        ),
      );
      _captures[captureId] = _copyFakeCaptureSession(
        session,
        updatedAt: now,
        turns: turns,
      );
    }
    return LocalCaptureUndoResult(
      undone: undone,
      entities: entities,
      failedEntities: failed,
    );
  }

  LocalCaptureSession _copyFakeCaptureSession(
    LocalCaptureSession session, {
    List<LocalCaptureAction>? actions,
    bool? committed,
    String? sessionStatus,
    DateTime? updatedAt,
    DateTime? expiresAt,
    Object? committedAt = _fakeCaptureUnchanged,
    Object? dismissedAt = _fakeCaptureUnchanged,
    List<LocalCaptureTurn>? turns,
  }) {
    return LocalCaptureSession(
      captureId: session.captureId,
      originalText: session.originalText,
      timezone: session.timezone,
      locale: session.locale,
      actions: actions ?? session.actions,
      requiresConfirmation: session.requiresConfirmation,
      committed: committed ?? session.committed,
      sessionStatus: sessionStatus ?? session.sessionStatus,
      sourceChannel: session.sourceChannel,
      createdAt: session.createdAt,
      updatedAt: updatedAt ?? session.updatedAt,
      expiresAt: expiresAt ?? session.expiresAt,
      committedAt: identical(committedAt, _fakeCaptureUnchanged)
          ? session.committedAt
          : committedAt as DateTime?,
      dismissedAt: identical(dismissedAt, _fakeCaptureUnchanged)
          ? session.dismissedAt
          : dismissedAt as DateTime?,
      turns: turns ?? session.turns,
    );
  }

  LocalCaptureTurn _copyFakeCaptureTurn(
    LocalCaptureTurn turn, {
    List<int>? selectedActionIndexes,
    List<LocalCoreEntityRef>? resultEntities,
    Object? undoToken = _fakeCaptureUnchanged,
    String? turnStatus,
    DateTime? updatedAt,
  }) {
    return LocalCaptureTurn(
      id: turn.id,
      captureId: turn.captureId,
      turnIndex: turn.turnIndex,
      role: turn.role,
      text: turn.text,
      assetIds: turn.assetIds,
      assetContext: turn.assetContext,
      actions: turn.actions,
      selectedActionIndexes:
          selectedActionIndexes ?? turn.selectedActionIndexes,
      resultEntities: resultEntities ?? turn.resultEntities,
      undoToken: identical(undoToken, _fakeCaptureUnchanged)
          ? turn.undoToken
          : undoToken as String?,
      supersedesTurnId: turn.supersedesTurnId,
      turnStatus: turnStatus ?? turn.turnStatus,
      createdAt: turn.createdAt,
      updatedAt: updatedAt ?? turn.updatedAt,
    );
  }

  List<LocalCaptureAssetContext> _fakeAssetContexts(List<String> assetIds) {
    final byId = {for (final asset in _assets) asset.id: asset};
    return assetIds
        .map(
          (assetId) => byId[assetId] == null
              ? LocalCaptureAssetContext(
                  assetId: assetId,
                  status: 'missing',
                  extractor: 'none',
                  error: 'asset_not_found',
                )
              : _fakeAssetContext(byId[assetId]!),
        )
        .toList(growable: false);
  }

  LocalCaptureAssetContext _fakeAssetContext(LocalAssetRecord asset) {
    return LocalCaptureAssetContext(
      assetId: asset.id,
      kind: asset.kind,
      assetType: asset.assetType,
      name: asset.title ?? asset.externalUrl ?? asset.id,
      sourceUrl: asset.externalUrl,
      status:
          asset.syncStatus == 'synced' ? 'metadata_only' : 'pending_upload',
      extractor:
          asset.kind == 'external' ? 'external_reference' : 'metadata',
      error: asset.syncStatus == 'synced'
          ? null
          : 'asset_sync_status_${asset.syncStatus}',
      requiredCapability: asset.kind == 'external'
          ? 'external_content_fetch'
          : 'binary_content_extractor',
    );
  }
}
