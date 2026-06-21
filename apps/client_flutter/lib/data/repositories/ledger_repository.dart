import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/domain/entities/ledger_transaction.dart';

class LedgerRepository {
  final ApiClient api;

  LedgerRepository(this.api);

  Future<List<LedgerTransaction>> list({
    int limit = 20,
    int offset = 0,
    String? direction,
    String? startDate,
    String? endDate,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (direction != null) params['direction'] = direction;
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;

    final res = await api.get('/ledger/transactions', params: params);
    final items = res['data']['items'] as List;
    return items.map((e) => LedgerTransaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<LedgerTransaction> create(Map<String, dynamic> data) async {
    final res = await api.post('/ledger/transactions', data: data);
    return LedgerTransaction.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> summary({String? startDate, String? endDate}) async {
    final params = <String, dynamic>{};
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;

    final res = await api.get('/ledger/summary', params: params);
    return res['data'] as Map<String, dynamic>;
  }
}
