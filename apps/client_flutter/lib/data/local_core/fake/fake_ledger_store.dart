part of '../fake_local_core_bridge.dart';

mixin _FakeLedgerStore on _FakeLocalCoreState {
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
              '${tx.merchant ?? ''}\n${tx.note ?? ''}'.toLowerCase().contains(q),
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
      budgetProgress:
          budget == null ? null : summary.totalExpense / budget.amount,
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
      throw ArgumentError(
        'alert_threshold must be greater than zero and at most one',
      );
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
      throw ArgumentError(
        'alert_threshold must be greater than zero and at most one',
      );
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
}
