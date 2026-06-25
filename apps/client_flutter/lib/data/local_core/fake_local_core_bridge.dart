import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';

class FakeLocalCoreBridge implements LocalCoreBridge {
  int _memoSeq = 0;
  int _expenseSeq = 0;
  int _taskSeq = 0;
  int _assetSeq = 0;
  int _captureSeq = 0;
  int _undoSeq = 0;

  final List<LocalMemoRecord> _memos = [];
  final List<LocalLedgerTransactionRecord> _expenses = [];
  final List<LocalTaskRecord> _tasks = [];
  final List<LocalAssetRecord> _assets = [];
  final Map<String, LocalCaptureSession> _captures = {};
  final Map<String, List<LocalCoreEntityRef>> _undoEntries = {};

  @override
  Future<LocalCoreHealth> health() async {
    return const LocalCoreHealth(status: 'ok', mode: 'fake', version: '0.1.0');
  }

  @override
  Future<LocalMemoRecord> createMemo(Map<String, Object?> input, LocalCoreContext context) async {
    final now = context.effectiveNow;
    final memo = LocalMemoRecord(
      id: _nextId('memo', ++_memoSeq),
      type: input['type'] as String? ?? 'memo',
      title: input['title'] as String?,
      contentMarkdown: input['content_markdown'] as String? ?? '',
      tags: (input['tags'] as List?)?.whereType<String>().toList() ?? const [],
      status: 'active',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    _memos.insert(0, memo);
    return memo;
  }

  @override
  Future<List<LocalMemoRecord>> searchMemos(Map<String, Object?> input, LocalCoreContext context) async {
    final q = (input['q'] as String? ?? '').trim().toLowerCase();
    final limit = input['limit'] as int? ?? 20;
    return _memos
        .where((memo) => memo.status == 'active')
        .where((memo) => q.isEmpty || '${memo.title ?? ''}\n${memo.contentMarkdown}'.toLowerCase().contains(q))
        .take(limit)
        .toList();
  }

  @override
  Future<LocalLedgerTransactionRecord> createExpense(Map<String, Object?> input, LocalCoreContext context) async {
    final now = context.effectiveNow;
    final tx = LocalLedgerTransactionRecord(
      id: _nextId('tx', ++_expenseSeq),
      direction: input['direction'] as String? ?? 'expense',
      amount: (input['amount'] as num).toDouble(),
      currency: input['currency'] as String? ?? 'CNY',
      merchant: input['merchant'] as String?,
      note: input['note'] as String?,
      occurredAt: DateTime.tryParse(input['occurred_at'] as String? ?? '') ?? now,
      status: 'active',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    _expenses.insert(0, tx);
    return tx;
  }

  @override
  Future<List<LocalLedgerTransactionRecord>> searchExpenses(Map<String, Object?> input, LocalCoreContext context) async {
    final q = (input['q'] as String? ?? '').trim().toLowerCase();
    final limit = input['limit'] as int? ?? 20;
    return _expenses
        .where((tx) => tx.status == 'active')
        .where((tx) => q.isEmpty || '${tx.merchant ?? ''}\n${tx.note ?? ''}'.toLowerCase().contains(q))
        .take(limit)
        .toList();
  }

  @override
  Future<LocalExpenseSummary> summarizeExpenses(Map<String, Object?> input, LocalCoreContext context) async {
    final active = _expenses.where((tx) => tx.status == 'active').toList();
    return LocalExpenseSummary(
      period: input['period'] as String? ?? 'current_month',
      totalExpense: active.where((tx) => tx.direction == 'expense').fold<double>(0, (sum, tx) => sum + tx.amount),
      totalIncome: active.where((tx) => tx.direction == 'income').fold<double>(0, (sum, tx) => sum + tx.amount),
      count: active.length,
    );
  }

  @override
  Future<LocalTaskRecord> createTask(Map<String, Object?> input, LocalCoreContext context) async {
    final now = context.effectiveNow;
    final task = LocalTaskRecord(
      id: _nextId('task', ++_taskSeq),
      title: input['title'] as String? ?? '',
      description: input['description'] as String?,
      dueAt: DateTime.tryParse(input['due_at'] as String? ?? ''),
      remindAt: DateTime.tryParse(input['remind_at'] as String? ?? ''),
      priority: input['priority'] as String? ?? 'normal',
      taskStatus: 'todo',
      completedAt: null,
      status: 'active',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    _tasks.insert(0, task);
    return task;
  }

  @override
  Future<List<LocalTaskRecord>> listTasks(Map<String, Object?> input, LocalCoreContext context) async {
    final taskStatus = input['task_status'] as String?;
    final limit = input['limit'] as int? ?? 20;
    return _tasks
        .where((task) => task.status == 'active')
        .where((task) => taskStatus == null || task.taskStatus == taskStatus)
        .take(limit)
        .toList();
  }

  @override
  Future<LocalTaskRecord> completeTask(Map<String, Object?> input, LocalCoreContext context) async {
    final taskId = input['task_id'] as String?;
    final index = _tasks.indexWhere((task) => task.id == taskId && task.status == 'active');
    if (index < 0) throw StateError('Task not found: $taskId');

    final old = _tasks[index];
    final now = context.effectiveNow;
    final updated = LocalTaskRecord(
      id: old.id,
      title: old.title,
      description: old.description,
      dueAt: old.dueAt,
      remindAt: old.remindAt,
      priority: old.priority,
      taskStatus: 'done',
      completedAt: now,
      status: old.status,
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: now,
    );
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<LocalAssetRecord> registerExternalAsset(Map<String, Object?> input, LocalCoreContext context) async {
    final now = context.effectiveNow;
    final asset = LocalAssetRecord(
      id: _nextId('asset', ++_assetSeq),
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
  Future<LocalCaptureSession> captureParse(Map<String, Object?> input, LocalCoreContext context) async {
    final session = LocalCaptureSession(
      captureId: _nextId('capture', ++_captureSeq),
      actions: [
        LocalCaptureAction(
          type: 'memo_create',
          payload: {
            'type': 'memo',
            'title': null,
            'content_markdown': input['text'] as String? ?? '',
            'tags': ['capture'],
          },
          confidence: 0.8,
        ),
      ],
      requiresConfirmation: false,
    );
    _captures[session.captureId] = session;
    return session;
  }

  @override
  Future<LocalCaptureCommitResult> captureCommit(Map<String, Object?> input, LocalCoreContext context) async {
    final captureId = input['capture_id'] as String?;
    final session = _captures[captureId];
    if (session == null) throw StateError('Capture not found: $captureId');

    final rawIndexes = input['selected_action_indexes'] as List?;
    final indexes = rawIndexes?.whereType<int>().toList() ?? List<int>.generate(session.actions.length, (index) => index);
    final created = <LocalCoreEntityRef>[];

    for (final index in indexes) {
      if (index < 0 || index >= session.actions.length) continue;
      final action = session.actions[index];
      if (action.type == 'memo_create') {
        final memo = await createMemo(action.payload, context);
        created.add(LocalCoreEntityRef(type: 'memo', id: memo.id));
      }
    }

    final undoToken = _nextId('undo', ++_undoSeq);
    _undoEntries[undoToken] = created;
    _captures.remove(captureId);
    return LocalCaptureCommitResult(committed: true, createdEntities: created, undoToken: undoToken);
  }

  @override
  Future<LocalCaptureUndoResult> captureUndo(Map<String, Object?> input, LocalCoreContext context) async {
    final undoToken = input['undo_token'] as String?;
    final entries = _undoEntries[undoToken];
    if (entries == null) throw StateError('Undo token not found: $undoToken');

    var undone = 0;
    final failed = <LocalCoreEntityRef>[];
    for (final entry in entries) {
      if (entry.type == 'memo') {
        final index = _memos.indexWhere((memo) => memo.id == entry.id);
        if (index >= 0) {
          final old = _memos[index];
          _memos[index] = LocalMemoRecord(
            id: old.id,
            type: old.type,
            title: old.title,
            contentMarkdown: old.contentMarkdown,
            tags: old.tags,
            status: 'ai_trashed',
            revision: old.revision + 1,
            createdAt: old.createdAt,
            updatedAt: context.effectiveNow,
          );
          undone += 1;
        } else {
          failed.add(entry);
        }
      } else {
        failed.add(entry);
      }
    }

    _undoEntries.remove(undoToken);
    return LocalCaptureUndoResult(undone: undone, failedEntities: failed);
  }

  String _nextId(String prefix, int seq) => 'local_${prefix}_${seq.toString().padLeft(4, '0')}';
}
