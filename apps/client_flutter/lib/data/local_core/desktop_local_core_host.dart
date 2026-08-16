import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';

class DesktopLocalCoreHost {
  final LocalCoreBridge _bridge;
  final String userId;

  const DesktopLocalCoreHost(
    this._bridge, {
    this.userId = defaultLocalCoreUserId,
  });

  Future<Map<String, Object?>> handle(Map<String, dynamic> request) async {
    final id = request['id'];
    if (id is! int) {
      return _error(0, 'request id must be an integer');
    }
    final method = request['method'];
    if (method is! String || method.isEmpty) {
      return _error(id, 'request method must be a non-empty string');
    }
    try {
      final input = _input(request['input']);
      final result = switch (method) {
        'health' => _health(await _bridge.health()),
        'memo_create' => _memo(
          await _bridge.createMemo(input, _context(request['context'], method)),
        ),
        'memo_search' => (await _bridge.searchMemos(
          input,
          _context(request['context'], method),
        )).map(_memo).toList(growable: false),
        'expense_create' => _expense(
          await _bridge.createExpense(
            input,
            _context(request['context'], method),
          ),
        ),
        'expense_search' => (await _bridge.searchExpenses(
          input,
          _context(request['context'], method),
        )).map(_expense).toList(growable: false),
        'expense_summary' => _expenseSummary(
          await _bridge.summarizeExpenses(
            input,
            _context(request['context'], method),
          ),
        ),
        'task_create' => _task(
          await _bridge.createTask(input, _context(request['context'], method)),
        ),
        'task_list' => (await _bridge.listTasks(
          input,
          _context(request['context'], method),
        )).map(_task).toList(growable: false),
        'task_complete' => _task(
          await _bridge.completeTask(
            input,
            _context(request['context'], method),
          ),
        ),
        'asset_register_external_url' => _asset(
          await _bridge.registerExternalAsset(
            input,
            _context(request['context'], method),
          ),
        ),
        'capture_parse' => _captureSession(
          await _bridge.captureParse(
            input,
            _context(request['context'], method),
          ),
        ),
        'capture_ingest_candidates' => _captureSession(
          await _bridge.captureIngestCandidates(
            input,
            _context(request['context'], method),
          ),
        ),
        'capture_commit' => _captureCommit(
          await _bridge.captureCommit(
            input,
            _context(request['context'], method),
          ),
        ),
        'capture_undo' => _captureUndo(
          await _bridge.captureUndo(
            input,
            _context(request['context'], method),
          ),
        ),
        _ => throw UnsupportedError(
          'Unsupported Desktop Local Core method: $method',
        ),
      };
      return {'id': id, 'ok': true, 'result': result};
    } catch (error) {
      return _error(id, _sanitizeError(error));
    }
  }

  Map<String, Object?> _input(Object? raw) {
    if (raw == null) return <String, Object?>{};
    if (raw is! Map) {
      throw const FormatException('Desktop Local Core input must be an object');
    }
    return raw.map((key, value) => MapEntry(key.toString(), value as Object?));
  }

  LocalCoreContext _context(Object? raw, String method) {
    final map = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    return LocalCoreContext(
      actorType: _actorType(map['actorType']),
      sourceChannel: _sourceChannel(map['sourceChannel']),
      userId: userId,
      actorId: _optionalString(map['actorId']),
      toolName: _optionalString(map['toolName']) ?? method,
      requestId: _optionalString(map['requestId']),
      sourceText: _optionalString(map['sourceText']),
      now: _optionalDateTime(map['now']),
    );
  }

  LocalCoreActorType _actorType(Object? raw) => switch (raw) {
    'user' => LocalCoreActorType.user,
    'system' => LocalCoreActorType.system,
    _ => LocalCoreActorType.ai,
  };

  LocalCoreSourceChannel _sourceChannel(Object? raw) => switch (raw) {
    'flutter' => LocalCoreSourceChannel.flutter,
    'cloud_mcp' => LocalCoreSourceChannel.cloudMcp,
    'import' => LocalCoreSourceChannel.import,
    'system' => LocalCoreSourceChannel.system,
    _ => LocalCoreSourceChannel.localMcp,
  };

  String? _optionalString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  DateTime? _optionalDateTime(Object? value) {
    final text = _optionalString(value);
    return text == null ? null : DateTime.parse(text).toUtc();
  }

  Map<String, Object?> _error(int id, String message) => {
    'id': id,
    'ok': false,
    'error': {'code': 'LOCAL_CORE_HOST_ERROR', 'message': message},
  };

  String _sanitizeError(Object error) {
    final text = error.toString();
    return text.length <= 512 ? text : '${text.substring(0, 512)}…';
  }
}

Map<String, Object?> _health(LocalCoreHealth value) => {
  'status': value.status,
  'mode': value.mode,
  'version': value.version,
  'runtime': 'desktop',
  if (value.detail != null) 'detail': value.detail,
};

Map<String, Object?> _memo(LocalMemoRecord value) => {
  'id': value.id,
  'type': value.type,
  'title': value.title,
  'content_markdown': value.contentMarkdown,
  'tags': value.tags,
  'status': value.status,
  'revision': value.revision,
  'created_at': value.createdAt.toUtc().toIso8601String(),
  'updated_at': value.updatedAt.toUtc().toIso8601String(),
};

Map<String, Object?> _expense(LocalLedgerTransactionRecord value) => {
  'id': value.id,
  'direction': value.direction,
  'amount': value.amount,
  'currency': value.currency,
  'merchant': value.merchant,
  'note': value.note,
  'category_hint': value.categoryId,
  'occurred_at': value.occurredAt.toUtc().toIso8601String(),
  'status': value.status,
  'revision': value.revision,
  'created_at': value.createdAt.toUtc().toIso8601String(),
  'updated_at': value.updatedAt.toUtc().toIso8601String(),
};

Map<String, Object?> _expenseSummary(LocalExpenseSummary value) => {
  'period': value.period,
  'total_expense': value.totalExpense,
  'total_income': value.totalIncome,
  'count': value.count,
};

Map<String, Object?> _task(LocalTaskRecord value) => {
  'id': value.id,
  'title': value.title,
  'description': value.description,
  'due_at': value.dueAt?.toUtc().toIso8601String(),
  'remind_at': value.remindAt?.toUtc().toIso8601String(),
  'priority': value.priority,
  'task_status': value.taskStatus,
  'completed_at': value.completedAt?.toUtc().toIso8601String(),
  'status': value.status,
  'revision': value.revision,
  'created_at': value.createdAt.toUtc().toIso8601String(),
  'updated_at': value.updatedAt.toUtc().toIso8601String(),
};

Map<String, Object?> _asset(LocalAssetRecord value) => {
  'id': value.id,
  'kind': value.kind,
  'asset_type': value.assetType,
  'title': value.title,
  'external_url': value.externalUrl,
  'sync_status': value.syncStatus,
  'status': 'active',
  'revision': value.revision,
  'created_at': value.createdAt.toUtc().toIso8601String(),
  'updated_at': value.updatedAt.toUtc().toIso8601String(),
};

Map<String, Object?> _captureAction(LocalCaptureAction value) => {
  'type': value.type,
  'payload': value.payload,
  'confidence': value.confidence,
};

Map<String, Object?> _captureSession(LocalCaptureSession value) => {
  'capture_id': value.captureId,
  'actions': value.actions.map(_captureAction).toList(growable: false),
  'requires_confirmation': value.requiresConfirmation,
};

Map<String, Object?> _entityRef(LocalCoreEntityRef value) => {
  'type': value.type,
  'id': value.id,
};

Map<String, Object?> _captureCommit(LocalCaptureCommitResult value) => {
  'committed': value.committed,
  'created_entities': value.createdEntities
      .map(_entityRef)
      .toList(growable: false),
  'failed_actions': value.failedEntities
      .map(
        (item) => <String, Object?>{
          'action_index': -1,
          'action_type': item.type,
          'reason': 'local_core_entity_failure',
          'detail': {'entity_id': item.id},
        },
      )
      .toList(growable: false),
  'undo_token': value.undoToken,
};

Map<String, Object?> _captureUndo(LocalCaptureUndoResult value) => {
  'undone': value.undone,
  'entities': value.entities.map(_entityRef).toList(growable: false),
  'failed_entities': value.failedEntities
      .map(_entityRef)
      .toList(growable: false),
};
