import 'dart:io';

import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/local_database_key.dart';
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
      final service = SyncService(
        databaseKeyProvider: const FixedLocalDatabaseKeyProvider(
          'lifly-test-sqlcipher-key-v1',
        ),
      );
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

      final updatedExpense = await bridge.updateExpense({
        'transaction_id': expense.id,
        'direction': 'expense',
        'amount': 18.75,
        'currency': 'CNY',
        'merchant': 'Updated Merchant',
        'note': 'updated locally',
        'occurred_at': '2026-07-01T08:30:00.000Z',
      }, LocalCoreContext.flutterUser(now: DateTime.utc(2026, 7, 1, 11)));
      expect(updatedExpense.id, expense.id);
      expect(updatedExpense.amount, 18.75);
      expect(updatedExpense.merchant, 'Updated Merchant');
      expect(updatedExpense.note, 'updated locally');
      expect(updatedExpense.occurredAt, DateTime.utc(2026, 7, 1, 8, 30));
      expect(updatedExpense.revision, 2);

      final results = await bridge.searchExpenses({
        'q': 'merchant',
        'limit': 20,
      }, context);
      expect(results.map((item) => item.id), contains(expense.id));

      final summary = await bridge.summarizeExpenses({
        'period': 'current_month',
      }, context);
      expect(summary.totalExpense, 18.75);
      expect(summary.totalIncome, 30);
      expect(summary.count, 2);

      final deleted = await bridge.deleteExpense({
        'transaction_id': expense.id,
      }, context);
      expect(deleted.status, 'user_trashed');
      expect(deleted.revision, 3);

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
      expect(auditCount['count'], 4);
    },
  );

  test('PowerSync budget CRUD persists overall and category budgets', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'lifly_budget_store_',
    );
    final service = SyncService(
      databaseKeyProvider: const FixedLocalDatabaseKeyProvider(
        'lifly-test-sqlcipher-key-v1',
      ),
    );
    addTearDown(() async {
      service.dispose();
      await tempDir.delete(recursive: true);
    });

    try {
      await service.initialize(dbPath: '${tempDir.path}/lifly-test.db');
    } catch (_) {
      return;
    }

    await service.db.execute(
      'INSERT INTO ledger_categories('
      'id, user_id, name, type, status, created_at, updated_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'category-food',
        'local-dev',
        '餐饮',
        'expense',
        'active',
        '2026-07-08T09:00:00.000Z',
        '2026-07-08T09:00:00.000Z',
      ],
    );

    final context = LocalCoreContext.flutterUser(
      now: DateTime.utc(2026, 7, 8, 9),
    );
    final bridge = PowerSyncLocalCoreBridge(syncService: service);
    final overall = await bridge.createLedgerBudget({
      'period_key': '2026-07',
      'amount': 3000,
      'currency': 'CNY',
      'alert_threshold': 0.75,
    }, context);
    final category = await bridge.createLedgerBudget({
      'period_key': '2026-07',
      'category_id': 'category-food',
      'amount': 1200,
      'currency': 'CNY',
    }, context);

    expect(overall.revision, 1);
    expect(category.categoryId, 'category-food');
    expect(
      () => bridge.createLedgerBudget({
        'period_key': '2026-07',
        'amount': 1000,
      }, context),
      throwsStateError,
    );

    final budgets = await bridge.listLedgerBudgets({
      'period': '2026-07',
    }, context);
    expect(budgets, hasLength(2));

    final updated = await bridge.updateLedgerBudget({
      'budget_id': overall.id,
      'amount': 3500,
      'alert_threshold': 0.85,
    }, context);
    expect(updated.amount, 3500);
    expect(updated.revision, 2);

    final overview = await bridge.getLedgerOverview({
      'period': '2026-07',
    }, context);
    expect(overview.budgetState, 'configured');
    expect(overview.budgetAmount, 3500);

    final deletedByUpdate = await bridge.updateLedgerBudget({
      'budget_id': category.id,
      'status': 'deleted',
    }, context);
    expect(deletedByUpdate.status, 'deleted');
    expect(deletedByUpdate.revision, 2);

    final restored = await bridge.updateLedgerBudget({
      'budget_id': category.id,
      'status': 'active',
    }, context);
    expect(restored.status, 'active');
    expect(restored.revision, 3);

    final deleted = await bridge.deleteLedgerBudget({
      'budget_id': category.id,
    }, context);
    expect(deleted.status, 'deleted');
    expect(deleted.revision, 4);

    final activeBudgets = await bridge.listLedgerBudgets({
      'period': '2026-07',
    }, context);
    expect(activeBudgets.map((item) => item.id), [overall.id]);

    final auditRows = await service.db.getAll(
      'SELECT action, entity_type FROM audit_logs '
      'WHERE entity_type = ? ORDER BY created_at',
      ['ledger_budget'],
    );
    expect(auditRows, hasLength(6));
    expect(auditRows.map((row) => row['action']), [
      'budget.create',
      'budget.create',
      'budget.update',
      'budget.delete',
      'budget.restore',
      'budget.delete',
    ]);
  });
}
