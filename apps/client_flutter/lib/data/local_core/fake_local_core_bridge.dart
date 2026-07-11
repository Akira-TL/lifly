import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_ids.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/local_home_overview_builder.dart';
import 'package:client_flutter/data/local_core/memo/local_memo_classification_engine.dart';
import 'package:client_flutter/data/local_core/task/local_task_reminder_strategy_engine.dart';

const Object _fakeReminderUnchanged = Object();
const Object _fakeCaptureUnchanged = Object();

class FakeLocalCoreBridge implements LocalCoreBridge {
  final LocalCoreIdGenerator _idGenerator;

  FakeLocalCoreBridge({LocalCoreIdGenerator? idGenerator})
    : _idGenerator = idGenerator ?? LocalCoreIdGenerator();

  final List<LocalMemoRecord> _memos = [];
  final List<LocalMemoClassification> _memoClassifications = [];
  final List<LocalTagMetadata> _tagMetadata = [];
  final List<LocalLedgerTransactionRecord> _expenses = [];
  final List<LocalLedgerBudget> _ledgerBudgets = [];
  final List<LocalTaskRecord> _tasks = [];
  final List<LocalTaskReminderStrategy> _taskReminderStrategies = [];
  final List<LocalReminderRecord> _reminders = [];
  final List<LocalAssetRecord> _assets = [];
  final Map<String, LocalCaptureSession> _captures = {};
  final Map<String, List<LocalCoreEntityRef>> _undoEntries = {};
  final Map<String, String> _undoCaptureIds = {};

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
    await generateMemoClassifications({'memo_id': memo.id}, context);
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
    await generateMemoClassifications({'memo_id': updated.id}, context);
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
  Future<List<LocalMemoClassification>> generateMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final memo = _memos.firstWhere(
      (item) => item.id == memoId && item.status == 'active',
    );
    _memoClassifications.removeWhere(
      (item) => item.memoId == memo.id && item.source == 'ai' && item.status == 'suggested',
    );
    final existing = _memoClassifications
        .where((item) => item.memoId == memo.id && item.status != 'rejected')
        .map((item) => item.tag)
        .toSet();
    final now = context.effectiveNow;
    for (final tag in memo.tags.where((tag) => tag.trim().isNotEmpty)) {
      _ensureFakeTagMetadata(tag.trim(), context);
      if (existing.add(tag.trim())) {
        _memoClassifications.add(
          LocalMemoClassification(
            id: _nextStableId('memo_cls'),
            memoId: memo.id,
            tag: tag.trim(),
            source: 'user',
            status: 'confirmed',
            confidence: 1,
            reason: '来自用户手动标签。',
            createdAt: now,
            updatedAt: now,
            confirmedAt: now,
          ),
        );
      }
    }
    for (final suggestion in const LocalMemoClassificationEngine().classify(memo)) {
      _ensureFakeTagMetadata(suggestion.tag, context);
      if (!existing.add(suggestion.tag)) continue;
      _memoClassifications.add(
        LocalMemoClassification(
          id: _nextStableId('memo_cls'),
          memoId: memo.id,
          tag: suggestion.tag,
          source: 'ai',
          status: 'suggested',
          confidence: suggestion.confidence,
          reason: suggestion.reason,
          createdAt: now,
          updatedAt: now,
          confirmedAt: null,
        ),
      );
    }
    return getMemoClassifications({'memo_id': memo.id}, context);
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

  @override
  Future<List<LocalTagMetadata>> listTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final kind = input['kind'] as String? ?? 'memo';
    final status = input['status'] as String? ?? 'active';
    return _tagMetadata
        .where((item) => item.kind == kind && item.status == status)
        .toList(growable: false)
      ..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
  }

  @override
  Future<LocalTagMetadata> upsertTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final name = (input['name'] as String?)?.trim();
    if (name == null || name.isEmpty) throw ArgumentError('name is required');
    return _ensureFakeTagMetadata(
      name,
      context,
      colorToken: input['color_token'] as String?,
      iconToken: input['icon_token'] as String?,
      sortOrder: input['sort_order'] as int?,
      status: input['status'] as String? ?? 'active',
      overrideExisting: true,
    );
  }

  @override
  Future<LocalTagMetadata> deleteTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final name = (input['name'] as String?)?.trim();
    if (name == null || name.isEmpty) throw ArgumentError('name is required');
    final index = _tagMetadata.indexWhere((item) => item.name == name);
    if (index < 0) throw StateError('Tag metadata not found: $name');
    final old = _tagMetadata[index];
    final updated = LocalTagMetadata(
      id: old.id,
      name: old.name,
      kind: old.kind,
      colorToken: old.colorToken,
      iconToken: old.iconToken,
      sortOrder: old.sortOrder,
      status: 'deleted',
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _tagMetadata[index] = updated;
    return updated;
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
    final period = _fakeBudgetPeriod(
      input['period'] as String? ?? 'current_month',
      context.effectiveNow,
    );
    final matchingBudgets = _ledgerBudgets
        .where(
          (item) =>
              item.status == 'active' &&
              item.periodKey == period &&
              item.categoryId == null,
        )
        .toList(growable: false);
    final budget = matchingBudgets.isEmpty ? null : matchingBudgets.first;
    return LocalLedgerOverview(
      schemaVersion: 'ledger_overview.v1',
      generatedAt: context.effectiveNow.toUtc(),
      period: period,
      sourceMode: input['source_mode'] as String? ?? 'local',
      monthIncome: summary.totalIncome,
      monthExpense: summary.totalExpense,
      transactionCount: summary.count,
      budgetState: budget == null ? 'not_configured' : 'configured',
      budgetAmount: budget?.amount,
      budgetUsed: budget == null ? null : summary.totalExpense,
      budgetProgress: budget == null
          ? null
          : summary.totalExpense / budget.amount,
      currency: budget?.currency ?? 'CNY',
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
  Future<List<LocalLedgerBudget>> listLedgerBudgets(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final period = _fakeBudgetPeriod(
      input['period'] as String? ?? 'current_month',
      context.effectiveNow,
    );
    final status = input['status'] as String? ?? 'active';
    final categoryId = input['category_id'] as String?;
    return _ledgerBudgets
        .where((item) => item.periodKey == period)
        .where((item) => status == 'all' || item.status == status)
        .where((item) => categoryId == null || item.categoryId == categoryId)
        .toList(growable: false);
  }

  @override
  Future<LocalLedgerBudget> createLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final periodKey = _fakeBudgetPeriod(
      input['period_key'] as String? ?? 'current_month',
      context.effectiveNow,
    );
    final categoryId = input['category_id'] as String?;
    final duplicate = _ledgerBudgets.any(
      (item) =>
          item.status == 'active' &&
          item.periodKey == periodKey &&
          item.categoryId == categoryId,
    );
    if (duplicate) {
      throw StateError(
        'An active budget already exists for this period and category',
      );
    }
    final amount = (input['amount'] as num?)?.toDouble();
    if (amount == null || amount <= 0) {
      throw ArgumentError('amount must be greater than zero');
    }
    final threshold = (input['alert_threshold'] as num?)?.toDouble() ?? 0.8;
    if (threshold <= 0 || threshold > 1) {
      throw ArgumentError('alert_threshold must be greater than zero and at most one');
    }
    final now = context.effectiveNow;
    final budget = LocalLedgerBudget(
      id: _nextStableId('budget'),
      periodType: 'month',
      periodKey: periodKey,
      categoryId: categoryId,
      amount: amount,
      currency: (input['currency'] as String? ?? 'CNY').toUpperCase(),
      alertThreshold: threshold,
      status: 'active',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    _ledgerBudgets.add(budget);
    return budget;
  }

  @override
  Future<LocalLedgerBudget> updateLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final budgetId = input['budget_id'] as String? ?? input['id'] as String?;
    final index = _ledgerBudgets.indexWhere((item) => item.id == budgetId);
    if (index < 0) throw StateError('Budget not found: $budgetId');
    final old = _ledgerBudgets[index];
    final periodKey = input.containsKey('period_key')
        ? _fakeBudgetPeriod(input['period_key'] as String, context.effectiveNow)
        : old.periodKey;
    final categoryId = input.containsKey('category_id')
        ? input['category_id'] as String?
        : old.categoryId;
    final amount = input.containsKey('amount')
        ? (input['amount'] as num).toDouble()
        : old.amount;
    if (amount <= 0) throw ArgumentError('amount must be greater than zero');
    final threshold = input.containsKey('alert_threshold')
        ? (input['alert_threshold'] as num?)?.toDouble()
        : old.alertThreshold;
    if (threshold != null && (threshold <= 0 || threshold > 1)) {
      throw ArgumentError('alert_threshold must be greater than zero and at most one');
    }
    final status = input['status'] as String? ?? old.status;
    final duplicate = status == 'active' &&
        _ledgerBudgets.any(
          (item) =>
              item.id != old.id &&
              item.status == 'active' &&
              item.periodKey == periodKey &&
              item.categoryId == categoryId,
        );
    if (duplicate) {
      throw StateError(
        'An active budget already exists for this period and category',
      );
    }
    final updated = LocalLedgerBudget(
      id: old.id,
      periodType: old.periodType,
      periodKey: periodKey,
      categoryId: categoryId,
      amount: amount,
      currency: (input['currency'] as String? ?? old.currency).toUpperCase(),
      alertThreshold: threshold,
      status: status,
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _ledgerBudgets[index] = updated;
    return updated;
  }

  @override
  Future<LocalLedgerBudget> deleteLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final budgetId = input['budget_id'] as String? ?? input['id'] as String?;
    final index = _ledgerBudgets.indexWhere((item) => item.id == budgetId);
    if (index < 0) throw StateError('Budget not found: $budgetId');
    final old = _ledgerBudgets[index];
    if (old.status == 'deleted') return old;
    final deleted = LocalLedgerBudget(
      id: old.id,
      periodType: old.periodType,
      periodKey: old.periodKey,
      categoryId: old.categoryId,
      amount: old.amount,
      currency: old.currency,
      alertThreshold: old.alertThreshold,
      status: 'deleted',
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _ledgerBudgets[index] = deleted;
    return deleted;
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
    await generateTaskReminderStrategy({'task_id': task.id}, context);
    return task;
  }

  @override
  Future<List<LocalTaskRecord>> listTasks(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskStatus = input['task_status'] as String?;
    final group = input['group'] as String? ?? 'all';
    final limit = input['limit'] as int? ?? 20;
    return _tasks
        .where((task) => task.status == 'active')
        .where((task) => taskStatus == null || task.taskStatus == taskStatus)
        .where((task) => _matchesTaskGroup(task, group, context.effectiveNow))
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
    _cancelFakeReminders(updated.id, context);
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
    if (updated.taskStatus == 'done' || updated.taskStatus == 'cancelled') {
      _cancelFakeReminders(updated.id, context);
    }
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
    _cancelFakeReminders(updated.id, context);
    return updated;
  }

  @override
  Future<LocalTaskReminderStrategy?> getTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    return _taskReminderStrategies
        .cast<LocalTaskReminderStrategy?>()
        .firstWhere(
          (item) =>
              item?.taskId == taskId && item?.strategyStatus != 'dismissed',
          orElse: () => null,
        );
  }

  @override
  Future<LocalTaskReminderStrategy?> generateTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final taskId = input['task_id'] as String? ?? input['id'] as String?;
    final task = _tasks.firstWhere(
      (item) => item.id == taskId && item.status == 'active',
    );
    final existing = await getTaskReminderStrategy({'task_id': task.id}, context);
    if (existing?.strategyStatus == 'confirmed') return existing;
    _taskReminderStrategies.removeWhere(
      (item) => item.taskId == task.id && item.source == 'ai' && item.strategyStatus == 'suggested',
    );
    final suggestion = const LocalTaskReminderStrategyEngine().suggest(
      task,
      now: context.effectiveNow,
    );
    if (suggestion == null) return null;
    final now = context.effectiveNow;
    final item = LocalTaskReminderStrategy(
      id: _nextStableId('task_strategy'),
      taskId: task.id,
      warningLevel: suggestion.warningLevel,
      warningReason: suggestion.warningReason,
      preparationWindowDays: suggestion.preparationWindowDays,
      aiSuggestedRemindAt: suggestion.aiSuggestedRemindAt,
      strategyStatus: 'suggested',
      source: 'ai',
      createdAt: now,
      updatedAt: now,
      confirmedAt: null,
      dismissedAt: null,
    );
    _taskReminderStrategies.add(item);
    return item;
  }

  @override
  Future<LocalTaskReminderStrategy> confirmTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final item = _upsertTaskReminderStrategy(input, context, 'confirmed');
    final remindAt = item.aiSuggestedRemindAt;
    if (remindAt != null) {
      await updateTask({
        'task_id': item.taskId,
        'remind_at': remindAt.toIso8601String(),
      }, context);
      _upsertFakeReminder(item, context);
    }
    return item;
  }

  @override
  Future<LocalTaskReminderStrategy> dismissTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final strategy = _upsertTaskReminderStrategy(input, context, 'dismissed');
    _cancelFakeReminders(strategy.taskId, context);
    return strategy;
  }

  @override
  Future<List<LocalReminderRecord>> listTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final status = input.containsKey('status')
        ? input['status'] as String?
        : input['reminder_status'] as String? ?? 'pending';
    final dueBefore = DateTime.tryParse(input['due_before'] as String? ?? '');
    final limit = input['limit'] as int? ?? 100;
    final items = _reminders
        .where((item) => item.targetType == 'task')
        .where((item) => status == null || item.status == status)
        .where(
          (item) => dueBefore == null || !item.remindAt.isAfter(dueBefore),
        )
        .toList()
      ..sort((a, b) => a.remindAt.compareTo(b.remindAt));
    return items.take(limit).toList(growable: false);
  }

  @override
  Future<List<LocalReminderRecord>> claimDueTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final now = DateTime.tryParse(input['now'] as String? ?? '') ??
        context.effectiveNow;
    final limit = input['limit'] as int? ?? 20;
    final leaseSeconds = input['lease_seconds'] as int? ?? 120;
    final candidates = _reminders
        .asMap()
        .entries
        .where(
          (entry) =>
              const {'pending', 'failed'}.contains(entry.value.status) &&
              !entry.value.remindAt.isAfter(now) &&
              entry.value.attemptCount < entry.value.maxAttempts &&
              (entry.value.nextAttemptAt == null ||
                  !entry.value.nextAttemptAt!.isAfter(now)) &&
              (entry.value.leaseUntil == null ||
                  !entry.value.leaseUntil!.isAfter(now)),
        )
        .take(limit)
        .toList();
    final claimed = <LocalReminderRecord>[];
    for (final entry in candidates) {
      final old = entry.value;
      final task = _tasks.cast<LocalTaskRecord?>().firstWhere(
            (item) =>
                item?.id == old.targetId &&
                item?.status == 'active' &&
                const {'todo', 'doing'}.contains(item?.taskStatus),
            orElse: () => null,
          );
      if (task == null) continue;
      final updated = _copyFakeReminder(
        old,
        status: 'pending',
        attemptCount: old.attemptCount + 1,
        nextAttemptAt: null,
        lastAttemptAt: now,
        dispatchToken: _nextStableId('reminder_claim'),
        leaseUntil: now.add(Duration(seconds: leaseSeconds)),
        revision: old.revision + 1,
        updatedAt: now,
        title: task.title,
        body: task.description,
      );
      _reminders[entry.key] = updated;
      claimed.add(updated);
    }
    return claimed;
  }

  @override
  Future<LocalReminderRecord> markTaskReminderDelivered(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final index = _fakeReminderIndex(input);
    final old = _reminders[index];
    if (old.status == 'delivered') return old;
    _requireFakeClaim(old, input['dispatch_token'] as String?);
    final updated = _copyFakeReminder(
      old,
      status: 'delivered',
      deliveredAt: context.effectiveNow,
      failedAt: null,
      cancelledAt: null,
      lastError: null,
      externalId: input['external_id'] as String? ?? old.externalId,
      dispatchToken: null,
      leaseUntil: null,
      nextAttemptAt: null,
      revision: old.revision + 1,
      updatedAt: context.effectiveNow,
    );
    _reminders[index] = updated;
    return updated;
  }

  @override
  Future<LocalReminderRecord> markTaskReminderFailed(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final index = _fakeReminderIndex(input);
    final old = _reminders[index];
    _requireFakeClaim(old, input['dispatch_token'] as String?);
    final error = (input['error'] as String? ?? '').trim();
    if (error.isEmpty) throw ArgumentError('error is required');
    final now = context.effectiveNow;
    final retryAfterSeconds = input['retry_after_seconds'] as int? ??
        _fakeRetryDelaySeconds(old.attemptCount);
    final updated = _copyFakeReminder(
      old,
      status: 'failed',
      failedAt: now,
      lastError: error,
      nextAttemptAt: old.attemptCount >= old.maxAttempts
          ? null
          : now.add(Duration(seconds: retryAfterSeconds)),
      dispatchToken: null,
      leaseUntil: null,
      revision: old.revision + 1,
      updatedAt: now,
    );
    _reminders[index] = updated;
    return updated;
  }

  @override
  Future<LocalReminderRecord> retryTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final index = _fakeReminderIndex(input);
    final old = _reminders[index];
    if (old.status == 'pending') return old;
    if (old.status != 'failed') {
      throw StateError('Reminder ${old.id} cannot retry from ${old.status}');
    }
    final updated = _copyFakeReminder(
      old,
      status: 'pending',
      attemptCount: (input['reset_attempts'] as bool? ?? true)
          ? 0
          : old.attemptCount,
      nextAttemptAt: context.effectiveNow,
      failedAt: null,
      lastError: null,
      dispatchToken: null,
      leaseUntil: null,
      revision: old.revision + 1,
      updatedAt: context.effectiveNow,
    );
    _reminders[index] = updated;
    return updated;
  }

  @override
  Future<LocalReminderRecord> cancelTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final index = _fakeReminderIndex(input);
    final old = _reminders[index];
    if (old.status == 'cancelled') return old;
    if (old.status == 'delivered') {
      throw StateError('Delivered reminder ${old.id} cannot be cancelled');
    }
    final updated = _copyFakeReminder(
      old,
      status: 'cancelled',
      cancelledAt: context.effectiveNow,
      nextAttemptAt: null,
      dispatchToken: null,
      leaseUntil: null,
      revision: old.revision + 1,
      updatedAt: context.effectiveNow,
    );
    _reminders[index] = updated;
    return updated;
  }

  void _upsertFakeReminder(
    LocalTaskReminderStrategy strategy,
    LocalCoreContext context,
  ) {
    final remindAt = strategy.aiSuggestedRemindAt;
    if (remindAt == null) return;
    final index = _reminders.indexWhere(
      (item) =>
          item.targetType == 'task' &&
          item.targetId == strategy.taskId &&
          const {'pending', 'failed'}.contains(item.status),
    );
    final old = index < 0 ? null : _reminders[index];
    final task = _tasks.cast<LocalTaskRecord?>().firstWhere(
          (item) => item?.id == strategy.taskId,
          orElse: () => null,
        );
    final item = LocalReminderRecord(
      id: old?.id ?? _nextStableId('reminder'),
      targetType: 'task',
      targetId: strategy.taskId,
      remindAt: remindAt,
      channel: 'app',
      status: 'pending',
      attemptCount: 0,
      maxAttempts: old?.maxAttempts ?? 3,
      nextAttemptAt: remindAt,
      lastAttemptAt: old?.lastAttemptAt,
      deliveredAt: null,
      failedAt: null,
      cancelledAt: null,
      lastError: null,
      externalId: old?.externalId,
      dispatchToken: null,
      leaseUntil: null,
      revision: (old?.revision ?? 0) + 1,
      createdAt: old?.createdAt ?? context.effectiveNow,
      updatedAt: context.effectiveNow,
      title: task?.title,
      body: task?.description,
    );
    if (index < 0) {
      _reminders.add(item);
    } else {
      _reminders[index] = item;
    }
  }

  LocalTaskReminderStrategy _upsertTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
    String status,
  ) {
    final strategyId =
        input['strategy_id'] as String? ?? input['id'] as String?;
    final taskId = input['task_id'] as String?;
    final index = strategyId == null
        ? _taskReminderStrategies.indexWhere((item) => item.taskId == taskId)
        : _taskReminderStrategies.indexWhere((item) => item.id == strategyId);
    final old = index < 0 ? null : _taskReminderStrategies[index];
    if (old == null && taskId == null) {
      throw ArgumentError(
        'task_id is required when strategy_id is not provided',
      );
    }
    final now = context.effectiveNow;
    final item = LocalTaskReminderStrategy(
      id: old?.id ?? _nextStableId('task_strategy'),
      taskId: old?.taskId ?? taskId!,
      warningLevel:
          input['warning_level'] as String? ?? old?.warningLevel ?? 'normal',
      warningReason: input['warning_reason'] as String? ?? old?.warningReason,
      preparationWindowDays:
          input['preparation_window_days'] as int? ??
          old?.preparationWindowDays,
      aiSuggestedRemindAt: input.containsKey('ai_suggested_remind_at')
          ? DateTime.tryParse(input['ai_suggested_remind_at'] as String? ?? '')
          : old?.aiSuggestedRemindAt,
      strategyStatus: status,
      source: input['source'] as String? ?? old?.source ?? 'user',
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      confirmedAt: status == 'confirmed' ? now : old?.confirmedAt,
      dismissedAt: status == 'dismissed' ? now : old?.dismissedAt,
    );
    if (index < 0) {
      _taskReminderStrategies.add(item);
    } else {
      _taskReminderStrategies[index] = item;
    }
    return item;
  }

  bool _matchesTaskGroup(LocalTaskRecord task, String group, DateTime now) {
    if (group == 'all') return true;
    if (task.taskStatus != 'todo' && task.taskStatus != 'doing') return false;
    final dueAt = task.dueAt;
    final strategy = _taskReminderStrategies
        .cast<LocalTaskReminderStrategy?>()
        .firstWhere(
          (item) =>
              item?.taskId == task.id && item?.strategyStatus != 'dismissed',
          orElse: () => null,
        );
    if (group == 'urgent') {
      return strategy?.warningLevel == 'critical' ||
          task.priority == 'urgent' ||
          (dueAt != null && dueAt.isBefore(now));
    }
    if (group == 'warning') {
      final warningDue =
          dueAt != null &&
          dueAt.isAfter(now) &&
          dueAt.difference(now).inDays <= 3;
      return strategy?.warningLevel == 'warning' ||
          task.priority == 'high' ||
          warningDue;
    }
    if (group == 'today') {
      if (dueAt == null) return false;
      final localDue = dueAt.toUtc();
      final localNow = now.toUtc();
      return localDue.year == localNow.year &&
          localDue.month == localNow.month &&
          localDue.day == localNow.day;
    }
    return true;
  }

  int _fakeReminderIndex(Map<String, Object?> input) {
    final reminderId = input['reminder_id'] as String? ?? input['id'] as String?;
    final index = _reminders.indexWhere((item) => item.id == reminderId);
    if (index < 0) throw StateError('Reminder not found: $reminderId');
    return index;
  }

  void _requireFakeClaim(
    LocalReminderRecord reminder,
    String? dispatchToken,
  ) {
    if (reminder.status == 'delivered' || reminder.status == 'cancelled') {
      throw StateError(
        'Reminder ${reminder.id} cannot transition from ${reminder.status}',
      );
    }
    if (dispatchToken == null || reminder.dispatchToken != dispatchToken) {
      throw StateError('Reminder ${reminder.id} dispatch token is stale');
    }
  }

  int _fakeRetryDelaySeconds(int attemptCount) {
    final exponent = attemptCount <= 1 ? 0 : attemptCount - 1;
    final clamped = exponent > 5 ? 5 : exponent;
    final seconds = 60 * (1 << clamped);
    return seconds > 3600 ? 3600 : seconds;
  }

  void _cancelFakeReminders(String taskId, LocalCoreContext context) {
    for (var index = 0; index < _reminders.length; index += 1) {
      final old = _reminders[index];
      if (old.targetType != 'task' ||
          old.targetId != taskId ||
          !const {'pending', 'failed'}.contains(old.status)) {
        continue;
      }
      _reminders[index] = _copyFakeReminder(
        old,
        status: 'cancelled',
        cancelledAt: context.effectiveNow,
        nextAttemptAt: null,
        dispatchToken: null,
        leaseUntil: null,
        revision: old.revision + 1,
        updatedAt: context.effectiveNow,
      );
    }
  }

  LocalReminderRecord _copyFakeReminder(
    LocalReminderRecord old, {
    String? status,
    int? attemptCount,
    int? maxAttempts,
    Object? nextAttemptAt = _fakeReminderUnchanged,
    Object? lastAttemptAt = _fakeReminderUnchanged,
    Object? deliveredAt = _fakeReminderUnchanged,
    Object? failedAt = _fakeReminderUnchanged,
    Object? cancelledAt = _fakeReminderUnchanged,
    Object? lastError = _fakeReminderUnchanged,
    Object? externalId = _fakeReminderUnchanged,
    Object? dispatchToken = _fakeReminderUnchanged,
    Object? leaseUntil = _fakeReminderUnchanged,
    int? revision,
    DateTime? updatedAt,
    Object? title = _fakeReminderUnchanged,
    Object? body = _fakeReminderUnchanged,
  }) {
    return LocalReminderRecord(
      id: old.id,
      targetType: old.targetType,
      targetId: old.targetId,
      remindAt: old.remindAt,
      channel: old.channel,
      status: status ?? old.status,
      attemptCount: attemptCount ?? old.attemptCount,
      maxAttempts: maxAttempts ?? old.maxAttempts,
      nextAttemptAt: identical(nextAttemptAt, _fakeReminderUnchanged)
          ? old.nextAttemptAt
          : nextAttemptAt as DateTime?,
      lastAttemptAt: identical(lastAttemptAt, _fakeReminderUnchanged)
          ? old.lastAttemptAt
          : lastAttemptAt as DateTime?,
      deliveredAt: identical(deliveredAt, _fakeReminderUnchanged)
          ? old.deliveredAt
          : deliveredAt as DateTime?,
      failedAt: identical(failedAt, _fakeReminderUnchanged)
          ? old.failedAt
          : failedAt as DateTime?,
      cancelledAt: identical(cancelledAt, _fakeReminderUnchanged)
          ? old.cancelledAt
          : cancelledAt as DateTime?,
      lastError: identical(lastError, _fakeReminderUnchanged)
          ? old.lastError
          : lastError as String?,
      externalId: identical(externalId, _fakeReminderUnchanged)
          ? old.externalId
          : externalId as String?,
      dispatchToken: identical(dispatchToken, _fakeReminderUnchanged)
          ? old.dispatchToken
          : dispatchToken as String?,
      leaseUntil: identical(leaseUntil, _fakeReminderUnchanged)
          ? old.leaseUntil
          : leaseUntil as DateTime?,
      revision: revision ?? old.revision,
      createdAt: old.createdAt,
      updatedAt: updatedAt ?? old.updatedAt,
      title: identical(title, _fakeReminderUnchanged)
          ? old.title
          : title as String?,
      body: identical(body, _fakeReminderUnchanged)
          ? old.body
          : body as String?,
    );
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
  Future<List<LocalCaptureAssetContext>> listCaptureAssets(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final limit = input['limit'] as int? ?? 50;
    return _assets
        .take(limit)
        .map(_fakeAssetContext)
        .toList(growable: false);
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
        (left, right) => (right.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(left.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
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
      confidence: (input['confidence'] as num?)?.toDouble() ?? oldAction.confidence,
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
          await deleteMemo({'memo_id': entry.id, 'status': 'ai_trashed'}, context);
        } else if (entry.type == 'task') {
          await deleteTask({'task_id': entry.id, 'status': 'ai_trashed'}, context);
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

  LocalTagMetadata _ensureFakeTagMetadata(
    String tag,
    LocalCoreContext context, {
    String? colorToken,
    String? iconToken,
    int? sortOrder,
    String status = 'active',
    bool overrideExisting = false,
  }) {
    final rule = const LocalMemoClassificationEngine().tagRuleFor(tag);
    final index = _tagMetadata.indexWhere(
      (item) => item.name == tag && item.kind == 'memo',
    );
    final old = index < 0 ? null : _tagMetadata[index];
    final resolved = LocalTagMetadata(
      id: old?.id ?? _nextStableId('tag_meta'),
      name: tag,
      kind: 'memo',
      colorToken: overrideExisting
          ? colorToken
          : old?.colorToken ?? colorToken ?? rule.colorToken,
      iconToken: overrideExisting
          ? iconToken
          : old?.iconToken ?? iconToken ?? rule.iconToken,
      sortOrder: overrideExisting
          ? sortOrder
          : old?.sortOrder ?? sortOrder ?? rule.sortOrder,
      status: status,
      createdAt: old?.createdAt ?? context.effectiveNow,
      updatedAt: context.effectiveNow,
    );
    if (index < 0) {
      _tagMetadata.add(resolved);
    } else {
      _tagMetadata[index] = resolved;
    }
    return resolved;
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
      status: asset.syncStatus == 'synced' ? 'metadata_only' : 'pending_upload',
      extractor: asset.kind == 'external' ? 'external_reference' : 'metadata',
      error: asset.syncStatus == 'synced'
          ? null
          : 'asset_sync_status_${asset.syncStatus}',
      requiredCapability: asset.kind == 'external'
          ? 'external_content_fetch'
          : 'binary_content_extractor',
    );
  }

  String _fakeBudgetPeriod(String period, DateTime now) {
    if (period == 'current_month') {
      final utc = now.toUtc();
      return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}';
    }
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      throw ArgumentError('period_key must use YYYY-MM');
    }
    return period;
  }

  String _nextStableId(String prefix) => _idGenerator.nextStable(prefix);
}
