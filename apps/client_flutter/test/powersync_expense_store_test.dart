import 'dart:io';

import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PowerSync expense flow persists when native database is available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'lifly_expense_store_',
      );
      final dbPath = '${tempDir.path}/lifly-test.db';
      final service = SyncService();
      addTearDown(() async {
        service.dispose();
        await tempDir.delete(recursive: true);
      });

      try {
        await service.initialize(dbPath: dbPath);
      } catch (_) {
        return;
      }

      final context = LocalCoreContext.flutterUser(
        now: DateTime.utc(2026, 7, 1, 10),
      );
      final bridge = PowerSyncLocalCoreBridge(syncService: service);

      final expense = await bridge.createExpense({
        'direction': 'expense',
        'amount': 12.5,
        'currency': 'CNY',
        'merchant': 'PowerSync Merchant',
        'note': 'local expense store',
        'occurred_at': '2026-07-01T08:00:00.000Z',
      }, context);
      final income = await bridge.createExpense({
        'direction': 'income',
        'amount': 30,
        'currency': 'CNY',
        'merchant': 'PowerSync Income',
        'note': 'local income store',
        'occurred_at': '2026-07-01T09:00:00.000Z',
      }, context);

      expect(expense.revision, 1);
      expect(income.revision, 1);

      final results = await bridge.searchExpenses({
        'q': 'merchant',
        'limit': 20,
      }, context);
      expect(results.map((item) => item.id), contains(expense.id));

      final summary = await bridge.summarizeExpenses({
        'period': 'current_month',
      }, context);
      expect(summary.totalExpense, 12.5);
      expect(summary.totalIncome, 30);
      expect(summary.count, 2);

      final deleted = await bridge.deleteExpense({
        'transaction_id': expense.id,
      }, context);
      expect(deleted.status, 'deleted');
      expect(deleted.revision, 2);

      final afterDelete = await bridge.searchExpenses({
        'q': 'merchant',
        'limit': 20,
      }, context);
      expect(afterDelete.map((item) => item.id), isNot(contains(expense.id)));

      final summaryAfterDelete = await bridge.summarizeExpenses({
        'period': 'current_month',
      }, context);
      expect(summaryAfterDelete.totalExpense, 0);
      expect(summaryAfterDelete.totalIncome, 30);
      expect(summaryAfterDelete.count, 1);

      final auditCount = await service.db.get(
        'SELECT count(*) AS count FROM audit_logs',
      );
      expect(auditCount['count'], 3);
    },
  );
}
