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
      occurredAt: createInput.occurredAt ?? context.effectiveNow,
      status: 'active',
      revision: metadata.revision,
      createdAt: metadata.timestamps.createdAt,
      updatedAt: metadata.timestamps.updatedAt,
    );

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      await _insertExpense(handle, tx, metadata);
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
      'SELECT id, direction, amount, currency, merchant, note, occurred_at, status, revision, created_at, updated_at '
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
      'SELECT id, direction, amount, currency, merchant, note, occurred_at, status, revision, created_at, updated_at '
      'FROM ledger_transactions WHERE id = ? AND status = ?',
      [transactionId, 'active'],
    );
    return row == null ? null : LocalExpenseMapper.fromRow(row);
  }

  Future<void> _insertExpense(
    LocalCoreWriteHandle handle,
    LocalLedgerTransactionRecord tx,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'INSERT INTO ledger_transactions('
      'id, user_id, direction, amount, currency, merchant, note, occurred_at, '
      'source, status, created_at, updated_at, revision'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        tx.id,
        metadata.userId,
        tx.direction,
        tx.amount,
        tx.currency,
        tx.merchant,
        tx.note,
        tx.occurredAt.toIso8601String(),
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
