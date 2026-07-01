import 'package:client_flutter/data/local_core/ledger/powersync_expense_store.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/memo/powersync_memo_store.dart';
import 'package:client_flutter/data/local_core/task/powersync_task_store.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

class PowerSyncLocalCoreBridge implements LocalCoreBridge {
  final SyncService syncService;
  final String version;
  late final PowerSyncExpenseStore _expenseStore = PowerSyncExpenseStore(
    syncService: syncService,
  );
  late final PowerSyncMemoStore _memoStore = PowerSyncMemoStore(
    syncService: syncService,
  );
  late final PowerSyncTaskStore _taskStore = PowerSyncTaskStore(
    syncService: syncService,
  );

  PowerSyncLocalCoreBridge({required this.syncService, this.version = '0.2.5'});

  @override
  Future<LocalCoreHealth> health() async {
    final checkedAt = DateTime.now().toUtc();

    try {
      await syncService.ensureInitialized();
      final probe = await syncService.db.get('SELECT 1 AS ok');
      final ok = probe['ok'] == 1;

      return LocalCoreHealth(
        status: ok ? 'ok' : 'error',
        mode: 'powersync',
        version: version,
        detail: ok
            ? 'database initialized at ${syncService.dbPath}'
            : 'database probe returned unexpected value: ${probe['ok']}',
        checkedAt: checkedAt,
      );
    } catch (error) {
      return LocalCoreHealth(
        status: 'error',
        mode: 'powersync',
        version: version,
        detail: error.toString(),
        checkedAt: checkedAt,
      );
    }
  }

  @override
  Future<LocalMemoRecord> createMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.createMemo(input, context);
  }

  @override
  Future<List<LocalMemoRecord>> searchMemos(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.searchMemos(input, context);
  }

  @override
  Future<LocalMemoRecord> updateMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.updateMemo(input, context);
  }

  @override
  Future<LocalMemoRecord> deleteMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.deleteMemo(input, context);
  }

  @override
  Future<LocalLedgerTransactionRecord> createExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.createExpense(input, context);
  }

  @override
  Future<List<LocalLedgerTransactionRecord>> searchExpenses(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.searchExpenses(input, context);
  }

  @override
  Future<LocalExpenseSummary> summarizeExpenses(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.summarizeExpenses(input, context);
  }

  @override
  Future<LocalLedgerTransactionRecord> deleteExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _unsupported('expense delete');
  }

  @override
  Future<LocalTaskRecord> createTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.createTask(input, context);
  }

  @override
  Future<List<LocalTaskRecord>> listTasks(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.listTasks(input, context);
  }

  @override
  Future<LocalTaskRecord> completeTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.completeTask(input, context);
  }

  @override
  Future<LocalTaskRecord> updateTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.updateTask(input, context);
  }

  @override
  Future<LocalTaskRecord> deleteTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.deleteTask(input, context);
  }

  @override
  Future<LocalAssetRecord> registerExternalAsset(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _unsupported('asset register');
  }

  @override
  Future<LocalCaptureSession> captureParse(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _unsupported('capture parse');
  }

  @override
  Future<LocalCaptureCommitResult> captureCommit(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _unsupported('capture commit');
  }

  @override
  Future<LocalCaptureUndoResult> captureUndo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _unsupported('capture undo');
  }

  Future<T> _unsupported<T>(String capability) {
    throw UnsupportedError(
      '$capability is planned after v0.2.1 local core foundation.',
    );
  }
}
