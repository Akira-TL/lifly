import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';
import 'package:client_flutter/domain/entities/ledger_transaction.dart';

class LedgerRepository {
  final ApiClient api;

  LedgerRepository(this.api);

  Future<PagedResult<LedgerTransaction>> listPage({
    int limit = 20,
    int offset = 0,
    String? direction,
    String? startDate,
    String? endDate,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (direction != null && direction.isNotEmpty) params['direction'] = direction;
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;

    final res = await api.get('/ledger/transactions', params: params);
    return PagedResult.fromData(res['data'] as Map<String, dynamic>, LedgerTransaction.fromJson);
  }

  Future<List<LedgerTransaction>> list({
    int limit = 20,
    int offset = 0,
    String? direction,
    String? startDate,
    String? endDate,
  }) async {
    final page = await listPage(limit: limit, offset: offset, direction: direction, startDate: startDate, endDate: endDate);
    return page.items;
  }

  Future<LedgerTransaction> get(String id) async {
    final res = await api.get('/ledger/transactions/$id');
    return LedgerTransaction.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<LedgerTransaction> create(Map<String, dynamic> data) async {
    final res = await api.post('/ledger/transactions', data: data);
    return LedgerTransaction.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<LedgerTransaction> update(String id, Map<String, dynamic> data) async {
    final res = await api.put('/ledger/transactions/$id', data: data);
    return LedgerTransaction.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await api.delete('/ledger/transactions/$id');
  }

  Future<Map<String, dynamic>> summary({String? startDate, String? endDate}) async {
    final params = <String, dynamic>{};
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;

    final res = await api.get('/ledger/summary', params: params);
    return res['data'] as Map<String, dynamic>;
  }
}
