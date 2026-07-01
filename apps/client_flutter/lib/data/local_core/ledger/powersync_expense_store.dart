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
}
