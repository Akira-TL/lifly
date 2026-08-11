import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/powersync_persistence_harness.dart';

void main() {
  test(
    'expense survives database restart with summary, soft delete, and audit logs',
    () async {
      final harness = await PowerSyncPersistenceHarness.create(
        'lifly_ledger_persistence_',
      );
      addTearDown(harness.dispose);

      final firstService = await harness.openService();
      if (firstService == null) return;

      final firstBridge = PowerSyncLocalCoreBridge(syncService: firstService);
      final context = LocalCoreContext.flutterUser(
        now: DateTime.utc(2026, 7, 2, 12),
      );

      final expense = await firstBridge.createExpense({
        'direction': 'expense',
        'amount': 18.5,
        'currency': 'CNY',
        'merchant': 'Persistent Merchant',
        'note': 'expense before restart',
        'occurred_at': '2026-07-02T08:00:00.000Z',
      }, context);
      final income = await firstBridge.createExpense({
        'direction': 'income',
        'amount': 30,
        'currency': 'CNY',
        'merchant': 'Persistent Income',
        'note': 'income before restart',
        'occurred_at': '2026-07-02T09:00:00.000Z',
      }, context);

      expect(expense.revision, 1);
      expect(income.revision, 1);
      firstService.dispose();

      final secondService = await harness.openService();
      expect(secondService, isNotNull);
      final secondBridge = PowerSyncLocalCoreBridge(
        syncService: secondService!,
      );

      final results = await secondBridge.searchExpenses({
        'q': 'persistent',
        'limit': 20,
      }, context);
      expect(results.map((item) => item.id), contains(expense.id));
      expect(results.map((item) => item.id), contains(income.id));

      final summary = await secondBridge.summarizeExpenses({
        'period': 'current_month',
      }, context);
      expect(summary.totalExpense, 18.5);
      expect(summary.totalIncome, 30);
      expect(summary.count, 2);

      final deleted = await secondBridge.deleteExpense({
        'transaction_id': expense.id,
      }, context);
      expect(deleted.revision, 2);
      expect(deleted.status, 'user_trashed');
      secondService.dispose();

      final thirdService = await harness.openService();
      expect(thirdService, isNotNull);
      final thirdBridge = PowerSyncLocalCoreBridge(syncService: thirdService!);

      final visibleAfterDelete = await thirdBridge.searchExpenses({
        'q': 'merchant',
        'limit': 20,
      }, context);
      expect(
        visibleAfterDelete.map((item) => item.id),
        isNot(contains(expense.id)),
      );

      final summaryAfterDelete = await thirdBridge.summarizeExpenses({
        'period': 'current_month',
      }, context);
      expect(summaryAfterDelete.totalExpense, 0);
      expect(summaryAfterDelete.totalIncome, 30);
      expect(summaryAfterDelete.count, 1);

      final deletedRow = await thirdService.db.get(
        'SELECT status, revision FROM ledger_transactions WHERE id = ?',
        [expense.id],
      );
      expect(deletedRow['status'], 'user_trashed');
      expect(deletedRow['revision'], 2);

      final restored = await thirdBridge.restoreExpense({
        'transaction_id': expense.id,
      }, context);
      expect(restored.status, 'active');
      expect(restored.revision, 3);
      expect(restored.amount, 18.5);

      final restoredRow = await thirdService.db.get(
        'SELECT status, revision, deleted_at FROM ledger_transactions WHERE id = ?',
        [expense.id],
      );
      expect(restoredRow['status'], 'active');
      expect(restoredRow['revision'], 3);
      expect(restoredRow['deleted_at'], isNull);

      final summaryAfterRestore = await thirdBridge.summarizeExpenses({
        'period': 'current_month',
      }, context);
      expect(summaryAfterRestore.totalExpense, 18.5);
      expect(summaryAfterRestore.totalIncome, 30);
      expect(summaryAfterRestore.count, 2);

      final auditRows = await thirdService.db.getAll(
        'SELECT action FROM audit_logs WHERE entity_type = ? AND entity_id = ? ORDER BY created_at',
        ['expense', expense.id],
      );
      expect(auditRows, hasLength(3));
      expect(auditRows.last['action'], 'expense.restore');
      thirdService.dispose();

      final fourthService = await harness.openService();
      expect(fourthService, isNotNull);
      final fourthBridge = PowerSyncLocalCoreBridge(syncService: fourthService!);
      final visibleAfterRestore = await fourthBridge.searchExpenses({
        'q': 'persistent merchant',
        'limit': 20,
      }, context);
      expect(visibleAfterRestore.map((item) => item.id), contains(expense.id));
      fourthService.dispose();
    },
  );
}
