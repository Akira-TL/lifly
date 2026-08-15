import 'package:client_flutter/data/local_core/capture/powersync_capture_store.dart';
import 'package:client_flutter/data/local_core/ledger/powersync_expense_store.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/local_home_overview_builder.dart';
import 'package:client_flutter/data/local_core/memo/powersync_memo_store.dart';
import 'package:client_flutter/data/local_core/task/powersync_task_store.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

class PowerSyncLocalCoreBridge implements LocalCoreBridge {
  final SyncService syncService;
  final String version;
  final AuditPayloadProtector? auditPayloadProtector;
  late final LocalCoreAuditLogWriter _auditLogWriter = LocalCoreAuditLogWriter(
    payloadProtector: auditPayloadProtector,
  );
  late final PowerSyncExpenseStore _expenseStore = PowerSyncExpenseStore(
    syncService: syncService,
    auditLogWriter: _auditLogWriter,
  );
  late final PowerSyncMemoStore _memoStore = PowerSyncMemoStore(
    syncService: syncService,
    auditLogWriter: _auditLogWriter,
  );
  late final PowerSyncTaskStore _taskStore = PowerSyncTaskStore(
    syncService: syncService,
    auditLogWriter: _auditLogWriter,
  );
  late final PowerSyncCaptureStore _captureStore = PowerSyncCaptureStore(
    syncService: syncService,
    memoStore: _memoStore,
    taskStore: _taskStore,
    expenseStore: _expenseStore,
  );

  PowerSyncLocalCoreBridge({
    required this.syncService,
    this.auditPayloadProtector,
    this.version = '0.2.5',
  });

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
  Future<LocalHomeOverview> getHomeOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final limit = input['limit'] as int? ?? 100;
    final memos = await _memoStore.searchMemos({'limit': limit}, context);
    final tasks = await _taskStore.listTasks({'limit': limit}, context);
    final transactions = await _expenseStore.searchExpenses({
      'limit': limit,
    }, context);
    final period = input['period'] as String? ?? 'current_month';
    final summary = await _expenseStore.summarizeExpenses({
      'period': period,
    }, context);
    final ledgerOverview = await _expenseStore.getLedgerOverview({
      'period': period,
      'source_mode': input['source_mode'] as String? ?? 'local',
    }, context);
    final categoryBreakdown = await _expenseStore.getLedgerCategorySummary({
      'period': period,
      'direction': 'expense',
    }, context);
    final financeInsights = await _expenseStore.getLedgerInsights({
      'period': period,
    }, context);
    final taskStrategies = await _taskStore.listTaskReminderStrategies();
    final sourceMode = input['source_mode'] as String? ?? 'local';
    final userTimezone = input['user_timezone'] as String? ?? 'local';
    final syncSummary = await _buildSyncSummary();
    final importSummary = await _buildImportSummary();
    return const LocalHomeOverviewBuilder().build(
      memos: memos,
      tasks: tasks,
      transactions: transactions,
      summary: summary,
      now: context.effectiveNow,
      ledgerOverview: ledgerOverview,
      categoryBreakdown: categoryBreakdown,
      financeInsights: financeInsights,
      taskStrategies: taskStrategies,
      syncSummary: syncSummary,
      importSummary: importSummary,
      settingsSummary: LocalHomeSettingsSummary(
        status: 'ok',
        dataMode: sourceMode,
        localCoreAvailable: true,
        databasePath: syncService.dbPath,
        timezone: userTimezone,
      ),
      userTimezone: userTimezone,
      sourceMode: sourceMode,
    );
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
  Future<LocalMemoRecord> restoreMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.restoreMemo(input, context);
  }

  @override
  Future<List<LocalMemoClassification>> getMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.getMemoClassifications(input, context);
  }

  @override
  Future<List<LocalMemoClassification>> generateMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.generateMemoClassifications(input, context);
  }

  @override
  Future<LocalMemoClassification> confirmMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.confirmMemoClassification(input, context);
  }

  @override
  Future<LocalMemoClassification> rejectMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.rejectMemoClassification(input, context);
  }

  @override
  Future<List<LocalTagSummary>> getTagSummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.getTagSummary(input, context);
  }

  @override
  Future<List<LocalTagMetadata>> listTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.listTagMetadata(input, context);
  }

  @override
  Future<LocalTagMetadata> upsertTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.upsertTagMetadata(input, context);
  }

  @override
  Future<LocalTagMetadata> deleteTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _memoStore.deleteTagMetadata(input, context);
  }

  @override
  Future<LocalLedgerTransactionRecord> createExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.createExpense(input, context);
  }

  @override
  Future<LocalLedgerTransactionRecord> updateExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.updateExpense(input, context);
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
  Future<LocalLedgerOverview> getLedgerOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.getLedgerOverview(input, context);
  }

  @override
  Future<List<LocalLedgerCategorySummary>> getLedgerCategorySummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.getLedgerCategorySummary(input, context);
  }

  @override
  Future<List<LocalLedgerInsight>> getLedgerInsights(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.getLedgerInsights(input, context);
  }

  @override
  Future<List<LocalLedgerBudget>> listLedgerBudgets(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.listLedgerBudgets(input, context);
  }

  @override
  Future<LocalLedgerBudget> createLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.createLedgerBudget(input, context);
  }

  @override
  Future<LocalLedgerBudget> updateLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.updateLedgerBudget(input, context);
  }

  @override
  Future<LocalLedgerBudget> deleteLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.deleteLedgerBudget(input, context);
  }

  @override
  Future<LocalLedgerTransactionRecord> deleteExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.deleteExpense(input, context);
  }

  @override
  Future<LocalLedgerTransactionRecord> restoreExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _expenseStore.restoreExpense(input, context);
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
  Future<LocalTaskRecord> restoreTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.restoreTask(input, context);
  }

  @override
  Future<LocalTaskReminderStrategy?> getTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.getTaskReminderStrategy(input, context);
  }

  @override
  Future<LocalTaskReminderStrategy?> generateTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.generateTaskReminderStrategy(input, context);
  }

  @override
  Future<LocalTaskReminderStrategy> confirmTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.confirmTaskReminderStrategy(input, context);
  }

  @override
  Future<LocalTaskReminderStrategy> dismissTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.dismissTaskReminderStrategy(input, context);
  }

  @override
  Future<List<LocalReminderRecord>> listTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.listTaskReminders(input, context);
  }

  @override
  Future<List<LocalReminderRecord>> claimDueTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.claimDueTaskReminders(input, context);
  }

  @override
  Future<LocalReminderRecord> markTaskReminderDelivered(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.markTaskReminderDelivered(input, context);
  }

  @override
  Future<LocalReminderRecord> markTaskReminderFailed(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.markTaskReminderFailed(input, context);
  }

  @override
  Future<LocalReminderRecord> retryTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.retryTaskReminder(input, context);
  }

  @override
  Future<LocalReminderRecord> cancelTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _taskStore.cancelTaskReminder(input, context);
  }

  @override
  Future<LocalAssetRecord> registerExternalAsset(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _unsupported('asset register');
  }

  @override
  Future<List<LocalCaptureAssetContext>> listCaptureAssets(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.listCaptureAssets(input, context);
  }

  @override
  Future<LocalCaptureSession> captureParse(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.captureParse(input, context);
  }

  @override
  Future<List<LocalCaptureSession>> listCaptureSessions(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.listCaptureSessions(input, context);
  }

  @override
  Future<LocalCaptureSession?> getCaptureSession(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.getCaptureSession(input, context);
  }

  @override
  Future<LocalCaptureSession> appendCaptureTurn(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.appendCaptureTurn(input, context);
  }

  @override
  Future<LocalCaptureTurn> reviseCaptureAction(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.reviseCaptureAction(input, context);
  }

  @override
  Future<LocalCaptureSession> dismissCaptureSession(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.dismissCaptureSession(input, context);
  }

  @override
  Future<LocalCaptureCommitResult> captureCommit(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.captureCommit(input, context);
  }

  @override
  Future<LocalCaptureUndoResult> captureUndo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) {
    return _captureStore.captureUndo(input, context);
  }

  Future<LocalHomeSyncSummary> _buildSyncSummary() async {
    await syncService.ensureInitialized();
    final status = syncService.db.currentStatus;
    final uploadDiagnostics = syncService.uploadDiagnostics;
    final assetCounts = await syncService.db.get(
      'SELECT '
      "SUM(CASE WHEN sync_status = 'pending' AND status = 'active' THEN 1 ELSE 0 END) AS pending_count, "
      "SUM(CASE WHEN sync_status = 'failed' AND status = 'active' THEN 1 ELSE 0 END) AS failed_count "
      'FROM assets',
    );
    final error =
        status.downloadError?.toString() ??
        status.uploadError?.toString() ??
        uploadDiagnostics.lastError;
    final pendingAssetCount = _readInt(assetCounts['pending_count']);
    final failedAssetCount = _readInt(assetCounts['failed_count']);
    final syncStatus = _syncStatusLabel(
      connected: status.connected,
      connecting: status.connecting,
      downloading: status.downloading,
      uploading: status.uploading,
      hasSynced: status.hasSynced,
      lastSyncedAt: status.lastSyncedAt,
      error: error,
    );

    return LocalHomeSyncSummary(
      status: failedAssetCount > 0
          ? 'error'
          : pendingAssetCount > 0 && syncStatus == 'synced'
          ? 'pending'
          : syncStatus,
      connected: status.connected,
      connecting: status.connecting,
      downloading: status.downloading,
      uploading: status.uploading,
      hasSynced: status.hasSynced,
      lastSyncedAt: status.lastSyncedAt,
      error: error,
      pendingAssetCount: pendingAssetCount,
      failedAssetCount: failedAssetCount,
    );
  }

  Future<LocalHomeImportSummary> _buildImportSummary() async {
    await syncService.ensureInitialized();
    final row = await syncService.db.getOptional(
      'SELECT id, source_provider, filename, status, total_rows, valid_rows, '
      'duplicate_rows, created_at, committed_at, rolled_back_at '
      'FROM import_batches ORDER BY created_at DESC LIMIT 1',
    );
    if (row == null) return const LocalHomeImportSummary.idle();

    return LocalHomeImportSummary(
      status: row['status'] as String? ?? 'idle',
      latestBatchId: row['id'] as String?,
      sourceProvider: row['source_provider'] as String?,
      filename: row['filename'] as String?,
      totalRows: _readInt(row['total_rows']),
      validRows: _readInt(row['valid_rows']),
      duplicateRows: _readInt(row['duplicate_rows']),
      createdAt: _readDateTime(row['created_at']),
      committedAt: _readDateTime(row['committed_at']),
      rolledBackAt: _readDateTime(row['rolled_back_at']),
    );
  }

  String _syncStatusLabel({
    required bool connected,
    required bool connecting,
    required bool downloading,
    required bool uploading,
    required bool? hasSynced,
    required DateTime? lastSyncedAt,
    required String? error,
  }) {
    if (error != null) return 'error';
    if (downloading) return 'downloading';
    if (uploading) return 'uploading';
    if (connecting) return 'connecting';
    if (connected && hasSynced == true) return 'synced';
    if (connected) return 'connected';
    if (lastSyncedAt != null) return 'offline';
    return 'local_only';
  }

  int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  DateTime? _readDateTime(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  Future<T> _unsupported<T>(String capability) {
    throw UnsupportedError(
      '$capability is planned after v0.2.1 local core foundation.',
    );
  }
}
