import 'package:client_flutter/data/local_core/ledger/local_expense_mapper.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

class PowerSyncExpenseStore {
  final SyncService syncService;
  final LocalCoreWritePolicy policy;
  final LocalCoreAuditLogWriter auditLogWriter;

  factory PowerSyncExpenseStore({
    required SyncService syncService,
    LocalCoreWritePolicy? policy,
    LocalCoreAuditLogWriter? auditLogWriter,
  }) {
    final resolvedPolicy = policy ?? LocalCoreWritePolicy();
    return PowerSyncExpenseStore._(
      syncService: syncService,
      policy: resolvedPolicy,
      auditLogWriter:
          auditLogWriter ?? LocalCoreAuditLogWriter(policy: resolvedPolicy),
    );
  }

  const PowerSyncExpenseStore._({
    required this.syncService,
    required this.policy,
    required this.auditLogWriter,
  });

  Future<LocalLedgerTransactionRecord> createExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final createInput = LocalExpenseCreateInput.fromMap(input);
    final metadata = policy.metadataForCreate(context);
    final tx = LocalLedgerTransactionRecord(
      id: policy.nextEntityId('tx'),
      direction: createInput.direction,
      amount: createInput.amount,
      currency: createInput.currency,
      merchant: createInput.merchant,
      note: createInput.note,
      categoryId: createInput.categoryId,
      occurredAt: createInput.occurredAt ?? context.effectiveNow,
      status: 'active',
      revision: metadata.revision,
      createdAt: metadata.timestamps.createdAt,
      updatedAt: metadata.timestamps.updatedAt,
    );

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      await _insertExpense(
        handle,
        tx,
        metadata,
        sourceCaptureId: createInput.sourceCaptureId,
      );
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'expense.create',
          entityType: 'expense',
          entityId: tx.id,
          afterSnapshot: LocalExpenseMapper.snapshot(tx),
        ),
      );
    });

    return tx;
  }

  Future<LocalLedgerTransactionRecord> updateExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final updateInput = LocalExpenseUpdateInput.fromMap(input);
    late final LocalLedgerTransactionRecord updatedTx;

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final oldTx = await _findActiveExpense(handle, updateInput.transactionId);
      if (oldTx == null) {
        throw StateError('Expense not found: ${updateInput.transactionId}');
      }
      if (updateInput.hasOccurredAt && updateInput.occurredAt == null) {
        throw ArgumentError('occurred_at is required when provided');
      }

      final metadata = policy.metadataForUpdate(
        context,
        currentRevision: oldTx.revision,
        createdAt: oldTx.createdAt,
      );
      updatedTx = LocalLedgerTransactionRecord(
        id: oldTx.id,
        direction: updateInput.direction ?? oldTx.direction,
        amount: updateInput.amount ?? oldTx.amount,
        currency: (updateInput.currency ?? oldTx.currency).toUpperCase(),
        merchant: updateInput.hasMerchant
            ? updateInput.merchant
            : oldTx.merchant,
        note: updateInput.hasNote ? updateInput.note : oldTx.note,
        categoryId: updateInput.hasCategoryId
            ? updateInput.categoryId
            : oldTx.categoryId,
        occurredAt: updateInput.hasOccurredAt
            ? updateInput.occurredAt!
            : oldTx.occurredAt,
        status: oldTx.status,
        revision: metadata.revision,
        createdAt: oldTx.createdAt,
        updatedAt: metadata.timestamps.updatedAt,
      );

      await _updateExpense(handle, updatedTx, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'expense.update',
          entityType: 'expense',
          entityId: updatedTx.id,
          beforeSnapshot: LocalExpenseMapper.snapshot(oldTx),
          afterSnapshot: LocalExpenseMapper.snapshot(updatedTx),
        ),
      );
    });

    return updatedTx;
  }

  Future<List<LocalLedgerTransactionRecord>> searchExpenses(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final searchInput = LocalExpenseSearchInput.fromMap(input);
    final rows = await _searchRows(
      query: searchInput.query,
      limit: searchInput.limit,
    );
    return rows.map(LocalExpenseMapper.fromRow).toList(growable: false);
  }

  Future<LocalLedgerOverview> getLedgerOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final period = input['period'] as String? ?? 'current_month';
    final sourceMode = input['source_mode'] as String? ?? 'local';
    final range = _periodRange(period, context.effectiveNow);
    final summary = await summarizeExpenses({'period': period}, context);
    await syncService.ensureInitialized();
    final budget = await syncService.db.getOptional(
      'SELECT amount, currency FROM ledger_budgets '
      'WHERE user_id = ? AND status = ? AND category_id IS NULL '
      'AND period_type = ? AND period_key = ? '
      'ORDER BY updated_at DESC LIMIT 1',
      [context.userId, 'active', 'month', range.periodKey],
    );
    final budgetAmount = (budget?['amount'] as num?)?.toDouble();
    final budgetUsed = budgetAmount == null ? null : summary.totalExpense;
    return LocalLedgerOverview(
      schemaVersion: 'ledger_overview.v1',
      generatedAt: context.effectiveNow.toUtc(),
      period: range.periodKey,
      sourceMode: sourceMode,
      monthIncome: summary.totalIncome,
      monthExpense: summary.totalExpense,
      transactionCount: summary.count,
      budgetState: budgetAmount == null ? 'not_configured' : 'configured',
      budgetAmount: budgetAmount,
      budgetUsed: budgetUsed,
      budgetProgress: budgetAmount == null || budgetAmount <= 0
          ? null
          : summary.totalExpense / budgetAmount,
      currency: budget?['currency'] as String? ?? 'CNY',
    );
  }

  Future<List<LocalLedgerCategorySummary>> getLedgerCategorySummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final direction = input['direction'] as String? ?? 'expense';
    final period = input['period'] as String? ?? 'current_month';
    final range = _periodRange(period, context.effectiveNow);
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT coalesce(t.category_id, ?) AS category_id, '
      'coalesce(c.name, ?) AS category_name, '
      'sum(t.amount) AS amount, count(*) AS transaction_count '
      'FROM ledger_transactions t '
      'LEFT JOIN ledger_categories c ON c.id = t.category_id '
      'WHERE t.status = ? AND t.direction = ? AND t.occurred_at >= ? AND t.occurred_at < ? '
      'GROUP BY coalesce(t.category_id, ?), coalesce(c.name, ?) '
      'ORDER BY amount DESC',
      [
        'uncategorized',
        '未分类',
        'active',
        direction,
        range.start.toIso8601String(),
        range.end.toIso8601String(),
        'uncategorized',
        '未分类',
      ],
    );
    final total = rows.fold<double>(
      0,
      (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
    );
    return rows
        .map((row) {
          final amount = (row['amount'] as num?)?.toDouble() ?? 0;
          return LocalLedgerCategorySummary(
            categoryId: row['category_id'] as String? ?? 'uncategorized',
            categoryName: row['category_name'] as String? ?? '未分类',
            direction: direction,
            amount: amount,
            ratio: total > 0 ? amount / total : 0,
            transactionCount: row['transaction_count'] as int? ?? 0,
          );
        })
        .toList(growable: false);
  }

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
    final progress = overview.budgetProgress ?? 0;
    if (progress >= 0.8) {
      return [
        LocalLedgerInsight(
          id: 'budget_progress_warning',
          type: 'budget',
          level: progress >= 1 ? 'critical' : 'warning',
          title: progress >= 1 ? '预算已超出' : '预算接近上限',
          description: '本月支出已达到预算的 ${(progress * 100).toStringAsFixed(0)}%。',
        ),
      ];
    }
    return const [];
  }

  Future<List<LocalLedgerBudget>> listLedgerBudgets(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final periodKey = _budgetPeriodKey(input['period'], context.effectiveNow);
    final status = _optionalString(input['status']) ?? 'active';
    if (!const {'active', 'deleted', 'all'}.contains(status)) {
      throw ArgumentError('status must be active, deleted, or all');
    }
    final categoryId = _optionalString(input['category_id']);
    await syncService.ensureInitialized();
    final conditions = <String>[
      'user_id = ?',
      'period_type = ?',
      'period_key = ?',
    ];
    final parameters = <Object?>[context.userId, 'month', periodKey];
    if (status != 'all') {
      conditions.add('status = ?');
      parameters.add(status);
    }
    if (categoryId != null) {
      conditions.add('category_id = ?');
      parameters.add(categoryId);
    }
    final rows = await syncService.db.getAll(
      'SELECT id, period_type, period_key, category_id, amount, currency, '
      'alert_threshold, status, revision, created_at, updated_at '
      'FROM ledger_budgets WHERE ${conditions.join(' AND ')} '
      'ORDER BY category_id IS NOT NULL, category_id, updated_at DESC',
      parameters,
    );
    return rows.map(_budgetFromRow).toList(growable: false);
  }

  Future<LocalLedgerBudget> createLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final periodType = _optionalString(input['period_type']) ?? 'month';
    if (periodType != 'month') {
      throw ArgumentError('period_type must be month');
    }
    final periodKey = _budgetPeriodKey(
      input['period_key'],
      context.effectiveNow,
    );
    final categoryId = _optionalString(input['category_id']);
    final amount = _positiveDouble(input['amount'], 'amount');
    final currency = (_optionalString(input['currency']) ?? 'CNY')
        .toUpperCase();
    final alertThreshold = _threshold(input['alert_threshold'], fallback: 0.8);
    final metadata = policy.metadataForCreate(context);
    final budget = LocalLedgerBudget(
      id: policy.nextEntityId('budget'),
      periodType: periodType,
      periodKey: periodKey,
      categoryId: categoryId,
      amount: amount,
      currency: currency,
      alertThreshold: alertThreshold,
      status: 'active',
      revision: metadata.revision,
      createdAt: metadata.timestamps.createdAt,
      updatedAt: metadata.timestamps.updatedAt,
    );

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      await _validateBudgetCategory(handle, categoryId, context.userId);
      await _ensureBudgetIdentityAvailable(
        handle,
        userId: context.userId,
        periodKey: periodKey,
        categoryId: categoryId,
      );
      await handle.execute(
        'INSERT INTO ledger_budgets('
        'id, user_id, period_type, period_key, category_id, amount, currency, '
        'alert_threshold, status, revision, created_at, updated_at'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          budget.id,
          metadata.userId,
          budget.periodType,
          budget.periodKey,
          budget.categoryId,
          budget.amount,
          budget.currency,
          budget.alertThreshold,
          budget.status,
          budget.revision,
          metadata.timestamps.createdAtIso,
          metadata.timestamps.updatedAtIso,
        ],
      );
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'budget.create',
          entityType: 'ledger_budget',
          entityId: budget.id,
          afterSnapshot: _budgetSnapshot(budget),
        ),
      );
    });
    return budget;
  }

  Future<LocalLedgerBudget> updateLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final budgetId = _requiredString(input, 'budget_id');
    late final LocalLedgerBudget updated;
    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final old = await _findBudget(handle, budgetId, context.userId);
      if (old == null) throw StateError('Budget not found: $budgetId');
      final periodKey = input.containsKey('period_key')
          ? _budgetPeriodKey(input['period_key'], context.effectiveNow)
          : old.periodKey;
      final categoryId = input.containsKey('category_id')
          ? _optionalString(input['category_id'])
          : old.categoryId;
      final amount = input.containsKey('amount')
          ? _positiveDouble(input['amount'], 'amount')
          : old.amount;
      final currency = input.containsKey('currency')
          ? _requiredString(input, 'currency').toUpperCase()
          : old.currency;
      final alertThreshold = input.containsKey('alert_threshold')
          ? _threshold(input['alert_threshold'])
          : old.alertThreshold;
      final status = _optionalString(input['status']) ?? old.status;
      if (!const {'active', 'deleted'}.contains(status)) {
        throw ArgumentError('status must be active or deleted');
      }
      await _validateBudgetCategory(handle, categoryId, context.userId);
      if (status == 'active') {
        await _ensureBudgetIdentityAvailable(
          handle,
          userId: context.userId,
          periodKey: periodKey,
          categoryId: categoryId,
          excludeId: old.id,
        );
      }
      final updatedAt = context.effectiveNow;
      updated = LocalLedgerBudget(
        id: old.id,
        periodType: old.periodType,
        periodKey: periodKey,
        categoryId: categoryId,
        amount: amount,
        currency: currency,
        alertThreshold: alertThreshold,
        status: status,
        revision: old.revision + 1,
        createdAt: old.createdAt,
        updatedAt: updatedAt,
      );
      await handle.execute(
        'UPDATE ledger_budgets SET period_key = ?, category_id = ?, amount = ?, '
        'currency = ?, alert_threshold = ?, status = ?, revision = ?, updated_at = ? WHERE id = ?',
        [
          updated.periodKey,
          updated.categoryId,
          updated.amount,
          updated.currency,
          updated.alertThreshold,
          updated.status,
          updated.revision,
          updated.updatedAt.toIso8601String(),
          updated.id,
        ],
      );
      final auditAction = old.status == 'deleted' && updated.status == 'active'
          ? 'budget.restore'
          : old.status == 'active' && updated.status == 'deleted'
          ? 'budget.delete'
          : 'budget.update';
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: auditAction,
          entityType: 'ledger_budget',
          entityId: updated.id,
          beforeSnapshot: _budgetSnapshot(old),
          afterSnapshot: _budgetSnapshot(updated),
        ),
      );
    });
    return updated;
  }

  Future<LocalLedgerBudget> deleteLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final budgetId = _requiredString(input, 'budget_id');
    late final LocalLedgerBudget deleted;
    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final old = await _findBudget(handle, budgetId, context.userId);
      if (old == null) throw StateError('Budget not found: $budgetId');
      if (old.status == 'deleted') {
        deleted = old;
        return;
      }
      deleted = LocalLedgerBudget(
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
      await handle.execute(
        'UPDATE ledger_budgets SET status = ?, revision = ?, updated_at = ? WHERE id = ?',
        [
          'deleted',
          deleted.revision,
          deleted.updatedAt.toIso8601String(),
          deleted.id,
        ],
      );
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'budget.delete',
          entityType: 'ledger_budget',
          entityId: deleted.id,
          beforeSnapshot: _budgetSnapshot(old),
          afterSnapshot: _budgetSnapshot(deleted),
        ),
      );
    });
    return deleted;
  }

  Future<LocalLedgerTransactionRecord> deleteExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final deleteInput = LocalExpenseDeleteInput.fromMap(input);
    late final LocalLedgerTransactionRecord deletedTx;

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final oldTx = await _findActiveExpense(handle, deleteInput.transactionId);
      if (oldTx == null) {
        throw StateError('Expense not found: ${deleteInput.transactionId}');
      }

      final metadata = policy.metadataForUpdate(
        context,
        currentRevision: oldTx.revision,
        createdAt: oldTx.createdAt,
      );
      deletedTx = LocalLedgerTransactionRecord(
        id: oldTx.id,
        direction: oldTx.direction,
        amount: oldTx.amount,
        currency: oldTx.currency,
        merchant: oldTx.merchant,
        note: oldTx.note,
        categoryId: oldTx.categoryId,
        occurredAt: oldTx.occurredAt,
        status: deleteInput.status,
        revision: metadata.revision,
        createdAt: oldTx.createdAt,
        updatedAt: metadata.timestamps.updatedAt,
      );

      await _softDeleteExpense(handle, deletedTx, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'expense.delete',
          entityType: 'expense',
          entityId: deletedTx.id,
          beforeSnapshot: LocalExpenseMapper.snapshot(oldTx),
          afterSnapshot: LocalExpenseMapper.snapshot(deletedTx),
        ),
      );
    });

    return deletedTx;
  }

  Future<LocalExpenseSummary> summarizeExpenses(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final summaryInput = LocalExpenseSummaryInput.fromMap(input);
    final range = _periodRange(summaryInput.period, context.effectiveNow);
    await syncService.ensureInitialized();
    final row = await syncService.db.get(
      'SELECT '
      'coalesce(sum(CASE WHEN direction = ? THEN amount ELSE 0 END), 0) AS total_expense, '
      'coalesce(sum(CASE WHEN direction = ? THEN amount ELSE 0 END), 0) AS total_income, '
      'count(*) AS count '
      'FROM ledger_transactions WHERE status = ? AND occurred_at >= ? AND occurred_at < ?',
      [
        'expense',
        'income',
        'active',
        range.start.toIso8601String(),
        range.end.toIso8601String(),
      ],
    );

    return LocalExpenseSummary(
      period: range.periodKey,
      totalExpense: (row['total_expense'] as num).toDouble(),
      totalIncome: (row['total_income'] as num).toDouble(),
      count: row['count'] as int,
    );
  }

  Future<List<Map<String, Object?>>> _searchRows({
    required String query,
    required int limit,
  }) async {
    await syncService.ensureInitialized();
    final likeQuery = '%$query%';
    final rows = await syncService.db.getAll(
      'SELECT id, direction, amount, currency, merchant, note, category_id, occurred_at, status, revision, created_at, updated_at '
      'FROM ledger_transactions '
      'WHERE status = ? AND (? = ? OR lower(coalesce(merchant, ?) || ? || coalesce(note, ?)) LIKE ?) '
      'ORDER BY occurred_at DESC, updated_at DESC '
      'LIMIT ?',
      ['active', query, '', '', '\n', '', likeQuery, limit],
    );
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<LocalLedgerTransactionRecord?> _findActiveExpense(
    LocalCoreWriteHandle handle,
    String transactionId,
  ) async {
    final row = await handle.getOptional(
      'SELECT id, direction, amount, currency, merchant, note, category_id, occurred_at, status, revision, created_at, updated_at '
      'FROM ledger_transactions WHERE id = ? AND status = ?',
      [transactionId, 'active'],
    );
    return row == null ? null : LocalExpenseMapper.fromRow(row);
  }

  Future<void> _insertExpense(
    LocalCoreWriteHandle handle,
    LocalLedgerTransactionRecord tx,
    LocalCoreWriteMetadata metadata, {
    String? sourceCaptureId,
  }) async {
    await handle.execute(
      'INSERT INTO ledger_transactions('
      'id, user_id, direction, amount, currency, merchant, note, category_id, occurred_at, '
      'source_capture_id, source, status, created_at, updated_at, revision'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        tx.id,
        metadata.userId,
        tx.direction,
        tx.amount,
        tx.currency,
        tx.merchant,
        tx.note,
        tx.categoryId,
        tx.occurredAt.toIso8601String(),
        sourceCaptureId,
        metadata.source,
        tx.status,
        metadata.timestamps.createdAtIso,
        metadata.timestamps.updatedAtIso,
        metadata.revision,
      ],
    );
  }

  Future<void> _updateExpense(
    LocalCoreWriteHandle handle,
    LocalLedgerTransactionRecord tx,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'UPDATE ledger_transactions SET direction = ?, amount = ?, currency = ?, '
      'merchant = ?, note = ?, category_id = ?, occurred_at = ?, updated_at = ?, revision = ? '
      'WHERE id = ? AND status = ?',
      [
        tx.direction,
        tx.amount,
        tx.currency,
        tx.merchant,
        tx.note,
        tx.categoryId,
        tx.occurredAt.toIso8601String(),
        metadata.timestamps.updatedAtIso,
        metadata.revision,
        tx.id,
        'active',
      ],
    );
  }

  Future<void> _softDeleteExpense(
    LocalCoreWriteHandle handle,
    LocalLedgerTransactionRecord tx,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'UPDATE ledger_transactions SET status = ?, deleted_at = ?, updated_at = ?, revision = ? '
      'WHERE id = ? AND status = ?',
      [
        tx.status,
        metadata.timestamps.updatedAtIso,
        metadata.timestamps.updatedAtIso,
        metadata.revision,
        tx.id,
        'active',
      ],
    );
  }

  Future<LocalLedgerBudget?> _findBudget(
    LocalCoreWriteHandle handle,
    String budgetId,
    String userId,
  ) async {
    final row = await handle.getOptional(
      'SELECT id, period_type, period_key, category_id, amount, currency, '
      'alert_threshold, status, revision, created_at, updated_at '
      'FROM ledger_budgets WHERE id = ? AND user_id = ?',
      [budgetId, userId],
    );
    return row == null ? null : _budgetFromRow(row);
  }

  Future<void> _validateBudgetCategory(
    LocalCoreWriteHandle handle,
    String? categoryId,
    String userId,
  ) async {
    if (categoryId == null) return;
    final row = await handle.getOptional(
      'SELECT type FROM ledger_categories '
      'WHERE id = ? AND user_id = ? AND status = ?',
      [categoryId, userId, 'active'],
    );
    if (row == null) {
      throw StateError('Budget category not found: $categoryId');
    }
    if (row['type'] != 'expense') {
      throw ArgumentError('Budget category must be an expense category');
    }
  }

  Future<void> _ensureBudgetIdentityAvailable(
    LocalCoreWriteHandle handle, {
    required String userId,
    required String periodKey,
    required String? categoryId,
    String? excludeId,
  }) async {
    final conditions = <String>[
      'user_id = ?',
      'period_type = ?',
      'period_key = ?',
      'status = ?',
      categoryId == null ? 'category_id IS NULL' : 'category_id = ?',
    ];
    final parameters = <Object?>[userId, 'month', periodKey, 'active'];
    if (categoryId != null) parameters.add(categoryId);
    if (excludeId != null) {
      conditions.add('id != ?');
      parameters.add(excludeId);
    }
    final existing = await handle.getOptional(
      'SELECT id FROM ledger_budgets WHERE ${conditions.join(' AND ')} LIMIT 1',
      parameters,
    );
    if (existing != null) {
      throw StateError(
        'An active budget already exists for this period and category',
      );
    }
  }

  LocalLedgerBudget _budgetFromRow(Map<String, Object?> row) {
    return LocalLedgerBudget(
      id: row['id'] as String,
      periodType: row['period_type'] as String? ?? 'month',
      periodKey: row['period_key'] as String,
      categoryId: row['category_id'] as String?,
      amount: (row['amount'] as num).toDouble(),
      currency: row['currency'] as String? ?? 'CNY',
      alertThreshold: (row['alert_threshold'] as num?)?.toDouble(),
      status: row['status'] as String? ?? 'active',
      revision: (row['revision'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> _budgetSnapshot(LocalLedgerBudget budget) {
    return {
      'id': budget.id,
      'period_type': budget.periodType,
      'period_key': budget.periodKey,
      'category_id': budget.categoryId,
      'amount': budget.amount,
      'currency': budget.currency,
      'alert_threshold': budget.alertThreshold,
      'status': budget.status,
      'revision': budget.revision,
      'created_at': budget.createdAt.toIso8601String(),
      'updated_at': budget.updatedAt.toIso8601String(),
    };
  }

  String _budgetPeriodKey(Object? value, DateTime now) {
    final raw = value is String && value.trim().isNotEmpty
        ? value.trim()
        : 'current_month';
    if (raw == 'current_month') {
      final utc = now.toUtc();
      return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}';
    }
    final match = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').firstMatch(raw);
    if (match == null) {
      throw ArgumentError('period_key must use YYYY-MM');
    }
    return raw;
  }

  String _requiredString(Map<String, Object?> input, String key) {
    final value = _optionalString(input[key]);
    if (value == null) throw ArgumentError('$key is required');
    return value;
  }

  String? _optionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double _positiveDouble(Object? value, String key) {
    if (value is! num || value <= 0) {
      throw ArgumentError('$key must be greater than zero');
    }
    return value.toDouble();
  }

  double? _threshold(Object? value, {double? fallback}) {
    if (value == null) return fallback;
    if (value is! num || value <= 0 || value > 1) {
      throw ArgumentError(
        'alert_threshold must be greater than zero and at most one',
      );
    }
    return value.toDouble();
  }

  _LedgerPeriodRange _periodRange(String period, DateTime now) {
    final normalized = period == 'current_month'
        ? '${now.toUtc().year.toString().padLeft(4, '0')}-${now.toUtc().month.toString().padLeft(2, '0')}'
        : period;
    final parts = normalized.split('-');
    if (parts.length != 2) {
      return _periodRange('current_month', now);
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return _periodRange('current_month', now);
    }
    final start = DateTime.utc(year, month, 1);
    final end = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    return _LedgerPeriodRange(
      periodKey:
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}',
      start: start,
      end: end,
    );
  }
}

class _LedgerPeriodRange {
  final String periodKey;
  final DateTime start;
  final DateTime end;

  const _LedgerPeriodRange({
    required this.periodKey,
    required this.start,
    required this.end,
  });
}
