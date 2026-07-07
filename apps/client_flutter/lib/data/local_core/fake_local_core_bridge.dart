import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_ids.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/local_home_overview_builder.dart';

class FakeLocalCoreBridge implements LocalCoreBridge {
  final LocalCoreIdGenerator _idGenerator;

  FakeLocalCoreBridge({LocalCoreIdGenerator? idGenerator})
    : _idGenerator = idGenerator ?? LocalCoreIdGenerator();

  final List<LocalMemoRecord> _memos = [];
  final List<LocalMemoClassification> _memoClassifications = [];
  final List<LocalLedgerTransactionRecord> _expenses = [];
  final List<LocalTaskRecord> _tasks = [];
  final List<LocalAssetRecord> _assets = [];
  final Map<String, LocalCaptureSession> _captures = {};
  final Map<String, List<LocalCoreEntityRef>> _undoEntries = {};

  @override
  Future<LocalCoreHealth> health() async {
    return LocalCoreHealth(
      status: 'ok',
      mode: 'fake',
      version: '0.2.1',
      detail: 'in-memory fallback bridge',
      checkedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<LocalHomeOverview> getHomeOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final summary = await summarizeExpenses({
      'period': input['period'] as String? ?? 'current_month',
    }, context);
    return const LocalHomeOverviewBuilder().build(
      memos: _memos,
      tasks: _tasks,
      transactions: _expenses,
      summary: summary,
      now: context.effectiveNow,
      sourceMode: input['source_mode'] as String? ?? 'local',
    );
  }

  @override
  Future<LocalMemoRecord> createMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final now = context.effectiveNow;
    final memo = LocalMemoRecord(
      id: _nextStableId('memo'),
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
  Future<List<LocalMemoRecord>> searchMemos(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final q = (input['q'] as String? ?? '').trim().toLowerCase();
    final limit = input['limit'] as int? ?? 20;
    return _memos
        .where((memo) => memo.status == 'active')
        .where(
          (memo) =>
              q.isEmpty ||
              '${memo.title ?? ''}\n${memo.contentMarkdown}'
                  .toLowerCase()
                  .contains(q),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<LocalMemoRecord> updateMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final index = _memos.indexWhere(
      (memo) => memo.id == memoId && memo.status == 'active',
    );
    if (index < 0) throw StateError('Memo not found: $memoId');

    final old = _memos[index];
    final updated = LocalMemoRecord(
      id: old.id,
      type: input['type'] as String? ?? old.type,
      title: input.containsKey('title') ? input['title'] as String? : old.title,
      contentMarkdown:
          input['content_markdown'] as String? ?? old.contentMarkdown,
      tags: (input['tags'] as List?)?.whereType<String>().toList() ?? old.tags,
      status: old.status,
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _memos[index] = updated;
    return updated;
  }

  @override
  Future<LocalMemoRecord> deleteMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final index = _memos.indexWhere(
      (memo) => memo.id == memoId && memo.status == 'active',
    );
    if (index < 0) throw StateError('Memo not found: $memoId');

    final old = _memos[index];
    final deleted = LocalMemoRecord(
      id: old.id,
      type: old.type,
      title: old.title,
      contentMarkdown: old.contentMarkdown,
      tags: old.tags,
      status: input['status'] as String? ?? 'deleted',
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _memos[index] = deleted;
    return deleted;
  }

  @override
  Future<List<LocalMemoClassification>> getMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final status = input['classification_status'] as String?;
    return _memoClassifications
        .where((item) => memoId == null || item.memoId == memoId)
        .where((item) => status == null || item.status == status)
        .toList(growable: false);
  }

  @override
  Future<LocalMemoClassification> confirmMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    return _upsertClassification(input, context, 'confirmed');
  }

  @override
  Future<LocalMemoClassification> rejectMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    return _upsertClassification(input, context, 'rejected');
  }

  @override
  Future<List<LocalTagSummary>> getTagSummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final counts = <String, List<LocalMemoClassification>>{};
    for (final item in _memoClassifications.where(
      (item) => item.status != 'rejected',
    )) {
      counts.putIfAbsent(item.tag, () => []).add(item);
    }
    return counts.entries
        .map((entry) {
          final confirmed = entry.value
              .where((item) => item.status == 'confirmed')
              .length;
          final suggested = entry.value
              .where((item) => item.status == 'suggested')
              .length;
          return LocalTagSummary(
            tag: entry.key,
            kind: input['kind'] as String? ?? 'memo',
            count: entry.value.length,
            confirmedCount: confirmed,
            suggestedCount: suggested,
            colorToken: null,
            iconToken: null,
            sortOrder: null,
          );
        })
        .toList(growable: false)
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  LocalMemoClassification _upsertClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
    String status,
  ) {
    final classificationId =
        input['classification_id'] as String? ?? input['id'] as String?;
    final memoId = input['memo_id'] as String?;
    final tag = input['tag'] as String?;
    final index = classificationId == null
        ? -1
        : _memoClassifications.indexWhere(
            (item) => item.id == classificationId,
          );
    final old = index < 0 ? null : _memoClassifications[index];
    if (old == null && (memoId == null || tag == null || tag.trim().isEmpty)) {
      throw ArgumentError(
        'memo_id and tag are required when classification_id is not provided',
      );
    }
    final now = context.effectiveNow;
    final item = LocalMemoClassification(
      id: old?.id ?? _nextStableId('memo_cls'),
      memoId: old?.memoId ?? memoId!,
      tag: old?.tag ?? tag!.trim(),
      source: old?.source ?? input['source'] as String? ?? 'user',
      status: status,
      confidence: old?.confidence ?? (input['confidence'] as num?)?.toDouble(),
      reason: old?.reason ?? input['reason'] as String?,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      confirmedAt: status == 'confirmed' ? now : null,
    );
    if (index < 0) {
      _memoClassifications.add(item);
    } else {
      _memoClassifications[index] = item;
    }
    return item;
  }

  @override
  Future<LocalLedgerTransactionRecord> createExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final now = context.effectiveNow;
    final tx = LocalLedgerTransactionRecord(
      id: _nextStableId('tx'),
      direction: input['direction'] as String? ?? 'expense',
      amount: (input['amount'] as num).toDouble(),
      currency: input['currency'] as String? ?? 'CNY',
      merchant: input['merchant'] as String?,
      note: input['note'] as String?,
      categoryId: input['category_id'] as String?,
      occurredAt:
          DateTime.tryParse(input['occurred_at'] as String? ?? '') ?? now,
      status: 'active',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    _expenses.insert(0, tx);
    return tx;
  }

  @override
  Future<List<LocalLedgerTransactionRecord>> searchExpenses(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final q = (input['q'] as String? ?? '').trim().toLowerCase();
    final limit = input['limit'] as int? ?? 20;
    return _expenses
        .where((tx) => tx.status == 'active')
        .where(
          (tx) =>
              q.isEmpty ||
              '${tx.merchant ?? ''}\n${tx.note ?? ''}'.toLowerCase().contains(
                q,
              ),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<LocalExpenseSummary> summarizeExpenses(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final active = _expenses.where((tx) => tx.status == 'active').toList();
    return LocalExpenseSummary(
      period: input['period'] as String? ?? 'current_month',
      totalExpense: active
          .where((tx) => tx.direction == 'expense')
          .fold<double>(0, (sum, tx) => sum + tx.amount),
      totalIncome: active
          .where((tx) => tx.direction == 'income')
          .fold<double>(0, (sum, tx) => sum + tx.amount),
      count: active.length,
    );
  }

  @override
  Future<LocalLedgerOverview> getLedgerOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final summary = await summarizeExpenses(input, context);
    return LocalLedgerOverview(
      schemaVersion: 'ledger_overview.v1',
      generatedAt: context.effectiveNow.toUtc(),
      period: summary.period,
      sourceMode: input['source_mode'] as String? ?? 'local',
      monthIncome: summary.totalIncome,
      monthExpense: summary.totalExpense,
      transactionCount: summary.count,
      budgetState: 'not_configured',
      budgetAmount: null,
      budgetUsed: null,
      budgetProgress: null,
      currency: 'CNY',
    );
  }

  @override
  Future<List<LocalLedgerCategorySummary>> getLedgerCategorySummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final direction = input['direction'] as String? ?? 'expense';
    final active = _expenses
        .where((tx) => tx.status == 'active' && tx.direction == direction)
        .toList();
    final total = active.fold<double>(0, (sum, tx) => sum + tx.amount);
    final grouped = <String, List<LocalLedgerTransactionRecord>>{};
    for (final tx in active) {
      grouped.putIfAbsent(tx.categoryId ?? 'uncategorized', () => []).add(tx);
    }
    return grouped.entries.map((entry) {
      final amount = entry.value.fold<double>(0, (sum, tx) => sum + tx.amount);
      return LocalLedgerCategorySummary(
        categoryId: entry.key,
        categoryName: entry.key == 'uncategorized' ? '未分类' : entry.key,
        direction: direction,
        amount: amount,
        ratio: total > 0 ? amount / total : 0,
        transactionCount: entry.value.length,
      );
    }).toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }

  @override
  Future<List<LocalLedgerInsight>> getLedgerInsights(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final overview = await getLedgerOverview(input, context);
    if (overview.budgetState == 'not_configured') {
      return const [
        LocalLedgerInsight(
          id: 'budget_not_configured',
          type: 'budget',
          level: 'info',
          title: '未设置预算',
          description: '设置月度预算后，可在首页看到预算进度和提醒。',
        ),
      ];
    }
    return const [];
  }

  @override
  Future<LocalLedgerTransactionRecord> deleteExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final transactionId =
        input['transaction_id'] as String? ??
        input['expense_id'] as String? ??
        input['id'] as String?;
    final index = _expenses.indexWhere(
      (tx) => tx.id == transactionId && tx.status == 'active',
    );
    if (index < 0) throw StateError('Expense not found: $transactionId');

    final old = _expenses[index];
    final deleted = LocalLedgerTransactionRecord(
      id: old.id,
      direction: old.direction,
      amount: old.amount,
      currency: old.currency,
      merchant: old.merchant,
      note: old.note,
      categoryId: old.categoryId,
      occurredAt: old.occurredAt,
      status: input['status'] as String? ?? 'deleted',
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _expenses[index] = deleted;
    return deleted;
  }

  @override
  Future<LocalTaskRecord> createTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final now = context.effectiveNow;
    final task = LocalTaskRecord(
      id: _nextStableId('task'),
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
  Future<List<LocalTaskRecord>> listTasks(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskStatus = input['task_status'] as String?;
    final limit = input['limit'] as int? ?? 20;
    return _tasks
        .where((task) => task.status == 'active')
        .where((task) => taskStatus == null || task.taskStatus == taskStatus)
        .take(limit)
        .toList();
  }

  @override
  Future<LocalTaskRecord> completeTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String?;
    final index = _tasks.indexWhere(
      (task) => task.id == taskId && task.status == 'active',
    );
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
  Future<LocalTaskRecord> updateTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    final index = _tasks.indexWhere(
      (task) => task.id == taskId && task.status == 'active',
    );
    if (index < 0) throw StateError('Task not found: $taskId');

    final old = _tasks[index];
    final updated = LocalTaskRecord(
      id: old.id,
      title: input['title'] as String? ?? old.title,
      description: input.containsKey('description')
          ? input['description'] as String?
          : old.description,
      dueAt: input.containsKey('due_at')
          ? DateTime.tryParse(input['due_at'] as String? ?? '')
          : old.dueAt,
      remindAt: input.containsKey('remind_at')
          ? DateTime.tryParse(input['remind_at'] as String? ?? '')
          : old.remindAt,
      priority: input['priority'] as String? ?? old.priority,
      taskStatus: input['task_status'] as String? ?? old.taskStatus,
      completedAt: old.completedAt,
      status: old.status,
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<LocalTaskRecord> deleteTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    final index = _tasks.indexWhere(
      (task) => task.id == taskId && task.status == 'active',
    );
    if (index < 0) throw StateError('Task not found: $taskId');

    final old = _tasks[index];
    final updated = LocalTaskRecord(
      id: old.id,
      title: old.title,
      description: old.description,
      dueAt: old.dueAt,
      remindAt: old.remindAt,
      priority: old.priority,
      taskStatus: old.taskStatus,
      completedAt: old.completedAt,
      status: input['status'] as String? ?? 'deleted',
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _tasks[index] = updated;
    return updated;
  }

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
  Future<LocalCaptureSession> captureParse(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final session = LocalCaptureSession(
      captureId: _nextStableId('capture'),
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
  Future<LocalCaptureCommitResult> captureCommit(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final captureId = input['capture_id'] as String?;
    final session = _captures[captureId];
    if (session == null) throw StateError('Capture not found: $captureId');

    final rawIndexes = input['selected_action_indexes'] as List?;
    final indexes =
        rawIndexes?.whereType<int>().toList() ??
        List<int>.generate(session.actions.length, (index) => index);
    final created = <LocalCoreEntityRef>[];

    for (final index in indexes) {
      if (index < 0 || index >= session.actions.length) continue;
      final action = session.actions[index];
      if (action.type == 'memo_create') {
        final memo = await createMemo(action.payload, context);
        created.add(LocalCoreEntityRef(type: 'memo', id: memo.id));
      }
    }

    final undoToken = _nextStableId('undo');
    _undoEntries[undoToken] = created;
    _captures.remove(captureId);
    return LocalCaptureCommitResult(
      committed: true,
      createdEntities: created,
      undoToken: undoToken,
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

  String _nextStableId(String prefix) => _idGenerator.nextStable(prefix);
}
