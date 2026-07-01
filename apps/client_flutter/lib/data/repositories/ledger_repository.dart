import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';
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

  LedgerTransaction _transactionFromLocal(LocalLedgerTransactionRecord record) {
    return LedgerTransaction(
      id: record.id,
      direction: record.direction,
      amount: record.amount,
      currency: record.currency,
      merchant: record.merchant,
      note: record.note,
      categoryId: null,
      occurredAt: record.occurredAt,
      source: 'local',
      createdAt: record.createdAt,
    );
  }
}
