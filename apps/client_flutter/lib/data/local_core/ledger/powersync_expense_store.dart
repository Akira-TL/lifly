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
    final summary = await summarizeExpenses({'period': period}, context);
    await syncService.ensureInitialized();
    final budget = await syncService.db.getOptional(
      'SELECT amount, currency FROM ledger_budgets '
      'WHERE status = ? AND category_id IS NULL AND (? = ? OR period_key = ?) '
      'ORDER BY updated_at DESC LIMIT 1',
      ['active', period, 'current_month', period],
    );
    final budgetAmount = (budget?['amount'] as num?)?.toDouble();
    final budgetUsed = budgetAmount == null ? null : summary.totalExpense;
    return LocalLedgerOverview(
      schemaVersion: 'ledger_overview.v1',
      generatedAt: context.effectiveNow.toUtc(),
      period: period,
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
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT coalesce(t.category_id, ?) AS category_id, '
      'coalesce(c.name, ?) AS category_name, '
      'sum(t.amount) AS amount, count(*) AS transaction_count '
      'FROM ledger_transactions t '
      'LEFT JOIN ledger_categories c ON c.id = t.category_id '
      'WHERE t.status = ? AND t.direction = ? '
      'GROUP BY coalesce(t.category_id, ?), coalesce(c.name, ?) '
      'ORDER BY amount DESC',
      ['uncategorized', '未分类', 'active', direction, 'uncategorized', '未分类'],
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
    await syncService.ensureInitialized();
    final row = await syncService.db.get(
      'SELECT '
      'coalesce(sum(CASE WHEN direction = ? THEN amount ELSE 0 END), 0) AS total_expense, '
      'coalesce(sum(CASE WHEN direction = ? THEN amount ELSE 0 END), 0) AS total_income, '
      'count(*) AS count '
      'FROM ledger_transactions WHERE status = ?',
      ['expense', 'income', 'active'],
    );

    return LocalExpenseSummary(
      period: summaryInput.period,
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
}
