import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';
import 'package:client_flutter/domain/entities/ledger_budget.dart';
import 'package:client_flutter/domain/entities/ledger_transaction.dart';

class LedgerRepository {
  final ApiClient api;
  final LocalCoreBridge? localCore;
  final LiflyDataMode dataMode;

  LedgerRepository(
    this.api, {
    this.localCore,
    this.dataMode = LiflyDataMode.api,
  });

  bool get _useLocalCore =>
      dataMode == LiflyDataMode.local && localCore != null;

  bool get _hasLocalCore => localCore != null;

  Future<PagedResult<LedgerTransaction>> listPage({
    int limit = 20,
    int offset = 0,
    String? direction,
    String? startDate,
    String? endDate,
  }) async {
    if (_useLocalCore) {
      final records = await localCore!.searchExpenses({
        'limit': limit + offset,
      }, LocalCoreContext.flutterUser());
      final filtered = direction == null || direction.isEmpty
          ? records
          : records.where((tx) => tx.direction == direction).toList();
      final pageItems = filtered
          .skip(offset)
          .take(limit)
          .map(_transactionFromLocal)
          .toList(growable: false);
      return PagedResult(
        items: pageItems,
        total: filtered.length,
        limit: limit,
        offset: offset,
      );
    }

    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (direction != null && direction.isNotEmpty) {
      params['direction'] = direction;
    }
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;

    final res = await api.get('/ledger/transactions', params: params);
    return PagedResult.fromData(
      res['data'] as Map<String, dynamic>,
      LedgerTransaction.fromJson,
    );
  }

  Future<List<LedgerTransaction>> list({
    int limit = 20,
    int offset = 0,
    String? direction,
    String? startDate,
    String? endDate,
  }) async {
    final page = await listPage(
      limit: limit,
      offset: offset,
      direction: direction,
      startDate: startDate,
      endDate: endDate,
    );
    return page.items;
  }

  Future<LedgerTransaction> get(String id) async {
    if (_useLocalCore) {
      final records = await localCore!.searchExpenses({
        'limit': 100,
      }, LocalCoreContext.flutterUser());
      for (final record in records) {
        if (record.id == id) return _transactionFromLocal(record);
      }
      throw StateError('Expense not found: $id');
    }

    final res = await api.get('/ledger/transactions/$id');
    return LedgerTransaction.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<LedgerTransaction> create(Map<String, dynamic> data) async {
    if (_useLocalCore) {
      final record = await localCore!.createExpense(
        data,
        LocalCoreContext.flutterUser(),
      );
      return _transactionFromLocal(record);
    }

    final res = await api.post('/ledger/transactions', data: data);
    return LedgerTransaction.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<LedgerTransaction> update(String id, Map<String, dynamic> data) async {
    if (_useLocalCore) {
      throw UnsupportedError(
        'Local Core expense update is not available in v0.2.6.',
      );
    }

    final res = await api.put('/ledger/transactions/$id', data: data);
    return LedgerTransaction.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    if (_useLocalCore) {
      await localCore!.deleteExpense({
        'transaction_id': id,
      }, LocalCoreContext.flutterUser());
      return;
    }

    await api.delete('/ledger/transactions/$id');
  }

  Future<List<LedgerBudget>> listBudgets({
    String period = 'current_month',
    String status = 'active',
    String? categoryId,
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final items = await localCore!.listLedgerBudgets({
        'period': period,
        'status': status,
        'category_id': ?categoryId,
      }, LocalCoreContext.flutterUser());
      return items.map(_budgetFromLocal).toList(growable: false);
    }

    try {
      final response = await api.get(
        '/ledger/budgets',
        params: {
          'period': period,
          'status': status,
          'category_id': ?categoryId,
        },
      );
      final items = response['data'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((item) => LedgerBudget.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (error) {
      if (_hasLocalCore) {
        final items = await localCore!.listLedgerBudgets({
          'period': period,
          'status': status,
          'category_id': ?categoryId,
        }, LocalCoreContext.flutterUser());
        return items.map(_budgetFromLocal).toList(growable: false);
      }
      throw StateError('Ledger budgets unavailable: $error');
    }
  }

  Future<LedgerBudget> createBudget(Map<String, dynamic> data) async {
    if (_useLocalCore) {
      return _budgetFromLocal(
        await localCore!.createLedgerBudget(
          data,
          LocalCoreContext.flutterUser(),
        ),
      );
    }
    final response = await api.post('/ledger/budgets', data: data);
    return LedgerBudget.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<LedgerBudget> updateBudget(
    String budgetId,
    Map<String, dynamic> data,
  ) async {
    if (_useLocalCore) {
      return _budgetFromLocal(
        await localCore!.updateLedgerBudget({
          ...data,
          'budget_id': budgetId,
        }, LocalCoreContext.flutterUser()),
      );
    }
    final response = await api.put('/ledger/budgets/$budgetId', data: data);
    return LedgerBudget.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<LedgerBudget> deleteBudget(String budgetId) async {
    if (_useLocalCore) {
      return _budgetFromLocal(
        await localCore!.deleteLedgerBudget({
          'budget_id': budgetId,
        }, LocalCoreContext.flutterUser()),
      );
    }
    final response = await api.delete('/ledger/budgets/$budgetId');
    return LedgerBudget.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> overview({
    String period = 'current_month',
  }) async {
    if (dataMode == LiflyDataMode.local) {
      return _ledgerOverviewToMap(
        await localCore!.getLedgerOverview({
          'period': period,
          'source_mode': 'local',
        }, LocalCoreContext.flutterUser()),
      );
    }

    try {
      final res = await api.get('/ledger/overview', params: {'period': period});
      return Map<String, dynamic>.from(res['data'] as Map);
    } catch (error) {
      if (_hasLocalCore) {
        return _ledgerOverviewToMap(
          await localCore!.getLedgerOverview({
            'period': period,
            'source_mode': 'fallback',
          }, LocalCoreContext.flutterUser()),
        );
      }
      throw StateError('Ledger overview unavailable: $error');
    }
  }

  Future<List<Map<String, dynamic>>> categorySummary({
    String period = 'current_month',
    String direction = 'expense',
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final items = await localCore!.getLedgerCategorySummary({
        'period': period,
        'direction': direction,
      }, LocalCoreContext.flutterUser());
      return items.map(_categorySummaryToMap).toList(growable: false);
    }

    try {
      final res = await api.get(
        '/ledger/categories/summary',
        params: {'period': period, 'direction': direction},
      );
      final items = res['data'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
    } catch (error) {
      if (_hasLocalCore) {
        final items = await localCore!.getLedgerCategorySummary({
          'period': period,
          'direction': direction,
        }, LocalCoreContext.flutterUser());
        return items.map(_categorySummaryToMap).toList(growable: false);
      }
      throw StateError('Ledger category summary unavailable: $error');
    }
  }

  Future<List<Map<String, dynamic>>> insights({
    String period = 'current_month',
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final items = await localCore!.getLedgerInsights({
        'period': period,
      }, LocalCoreContext.flutterUser());
      return items.map(_insightToMap).toList(growable: false);
    }

    try {
      final res = await api.get('/ledger/insights', params: {'period': period});
      final items = res['data'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
    } catch (error) {
      if (_hasLocalCore) {
        final items = await localCore!.getLedgerInsights({
          'period': period,
        }, LocalCoreContext.flutterUser());
        return items.map(_insightToMap).toList(growable: false);
      }
      throw StateError('Ledger insights unavailable: $error');
    }
  }

  Future<Map<String, dynamic>> summary({
    String? startDate,
    String? endDate,
  }) async {
    if (_useLocalCore) {
      final summary = await localCore!.summarizeExpenses({
        'period': 'current_month',
      }, LocalCoreContext.flutterUser());
      return {
        'income_total': summary.totalIncome,
        'expense_total': summary.totalExpense,
        'transaction_count': summary.count,
      };
    }

    final params = <String, dynamic>{};
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;

    final res = await api.get('/ledger/summary', params: params);
    return res['data'] as Map<String, dynamic>;
  }

  LedgerBudget _budgetFromLocal(LocalLedgerBudget budget) {
    return LedgerBudget(
      id: budget.id,
      periodType: budget.periodType,
      periodKey: budget.periodKey,
      categoryId: budget.categoryId,
      categoryName: null,
      amount: budget.amount,
      currency: budget.currency,
      alertThreshold: budget.alertThreshold,
      status: budget.status,
      revision: budget.revision,
      createdAt: budget.createdAt,
      updatedAt: budget.updatedAt,
    );
  }

  LedgerTransaction _transactionFromLocal(LocalLedgerTransactionRecord record) {
    return LedgerTransaction(
      id: record.id,
      direction: record.direction,
      amount: record.amount,
      currency: record.currency,
      merchant: record.merchant,
      note: record.note,
      categoryId: record.categoryId,
      occurredAt: record.occurredAt,
      source: 'local',
      createdAt: record.createdAt,
    );
  }

  Map<String, dynamic> _ledgerOverviewToMap(LocalLedgerOverview overview) {
    return {
      'schema_version': overview.schemaVersion,
      'generated_at': overview.generatedAt.toIso8601String(),
      'period': overview.period,
      'source_mode': overview.sourceMode,
      'month_income': overview.monthIncome,
      'month_expense': overview.monthExpense,
      'transaction_count': overview.transactionCount,
      'budget_state': overview.budgetState,
      'budget_amount': overview.budgetAmount,
      'budget_used': overview.budgetUsed,
      'budget_progress': overview.budgetProgress,
      'currency': overview.currency,
    };
  }

  Map<String, dynamic> _categorySummaryToMap(LocalLedgerCategorySummary item) {
    return {
      'category_id': item.categoryId,
      'category_name': item.categoryName,
      'direction': item.direction,
      'amount': item.amount,
      'ratio': item.ratio,
      'transaction_count': item.transactionCount,
    };
  }

  Map<String, dynamic> _insightToMap(LocalLedgerInsight item) {
    return {
      'id': item.id,
      'type': item.type,
      'level': item.level,
      'title': item.title,
      'description': item.description,
    };
  }
}
