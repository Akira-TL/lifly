import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';

abstract class LocalCoreBridge {
  Future<LocalCoreHealth> health();
  Future<LocalHomeOverview> getHomeOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  );

  Future<LocalMemoRecord> createMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalMemoRecord>> searchMemos(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalMemoRecord> updateMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalMemoRecord> deleteMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalMemoRecord> restoreMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalMemoClassification>> getMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalMemoClassification>> generateMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalMemoClassification> confirmMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalMemoClassification> rejectMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalTagSummary>> getTagSummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalTagMetadata>> listTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTagMetadata> upsertTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTagMetadata> deleteTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  );

  Future<LocalLedgerTransactionRecord> createExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalLedgerTransactionRecord> updateExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalLedgerTransactionRecord>> searchExpenses(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalExpenseSummary> summarizeExpenses(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalLedgerOverview> getLedgerOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalLedgerCategorySummary>> getLedgerCategorySummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalLedgerInsight>> getLedgerInsights(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalLedgerBudget>> listLedgerBudgets(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalLedgerBudget> createLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalLedgerBudget> updateLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalLedgerBudget> deleteLedgerBudget(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalLedgerTransactionRecord> deleteExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalLedgerTransactionRecord> restoreExpense(
    Map<String, Object?> input,
    LocalCoreContext context,
  );

  Future<LocalTaskRecord> createTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalTaskRecord>> listTasks(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTaskRecord> completeTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTaskRecord> updateTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTaskRecord> deleteTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTaskRecord> restoreTask(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTaskReminderStrategy?> getTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTaskReminderStrategy?> generateTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTaskReminderStrategy> confirmTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalTaskReminderStrategy> dismissTaskReminderStrategy(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalReminderRecord>> listTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalReminderRecord>> claimDueTaskReminders(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalReminderRecord> markTaskReminderDelivered(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalReminderRecord> markTaskReminderFailed(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalReminderRecord> retryTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalReminderRecord> cancelTaskReminder(
    Map<String, Object?> input,
    LocalCoreContext context,
  );

  Future<LocalAssetRecord> registerExternalAsset(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalCaptureAssetContext>> listCaptureAssets(
    Map<String, Object?> input,
    LocalCoreContext context,
  );

  Future<LocalCaptureSession> captureParse(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<List<LocalCaptureSession>> listCaptureSessions(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalCaptureSession?> getCaptureSession(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalCaptureSession> appendCaptureTurn(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalCaptureTurn> reviseCaptureAction(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalCaptureSession> dismissCaptureSession(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalCaptureCommitResult> captureCommit(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
  Future<LocalCaptureUndoResult> captureUndo(
    Map<String, Object?> input,
    LocalCoreContext context,
  );
}
