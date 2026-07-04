import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/import_export/pages/import_batches_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ImportBatchesPage lists batches and filters by status', (
    tester,
  ) async {
    final api = _FakeApiClient()
      ..batchResponses[''] = _batchPage(
        total: 2,
        offset: 0,
        items: [
          _batch(
            id: 'batch-001',
            filename: 'wechat.csv',
            sourceProvider: 'wechat',
            status: 'preview',
            totalRows: 3,
            validRows: 2,
          ),
          _batch(
            id: 'batch-002',
            filename: 'alipay.csv',
            sourceProvider: 'alipay',
            status: 'committed',
            totalRows: 5,
            validRows: 5,
          ),
        ],
      )
      ..batchResponses['committed'] = _batchPage(
        total: 1,
        offset: 0,
        items: [
          _batch(
            id: 'batch-002',
            filename: 'alipay.csv',
            sourceProvider: 'alipay',
            status: 'committed',
            totalRows: 5,
            validRows: 5,
          ),
        ],
      );

    await tester.pumpWidget(_buildPage(api));
    await tester.pumpAndSettle();

    expect(find.text('导入批次'), findsOneWidget);
    expect(find.text('wechat.csv'), findsOneWidget);
    expect(find.text('alipay.csv'), findsOneWidget);
    expect(find.textContaining('微信支付 · 2/3 有效'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '已提交'));
    await tester.pumpAndSettle();

    expect(api.calls.map((call) => call.status), [null, 'committed']);
    expect(find.text('wechat.csv'), findsNothing);
    expect(find.text('alipay.csv'), findsOneWidget);
  });

  testWidgets('ImportBatchesPage opens preview detail from batch item', (
    tester,
  ) async {
    final api = _FakeApiClient()
      ..batchResponses[''] = _batchPage(
        total: 1,
        offset: 0,
        items: [
          _batch(
            id: 'batch-001',
            filename: 'wechat.csv',
            sourceProvider: 'wechat',
            status: 'preview',
            totalRows: 1,
            validRows: 1,
          ),
        ],
      )
      ..previewResponse = {
        'data': {
          'batch': {
            'id': 'batch-001',
            'status': 'preview',
            'filename': 'wechat.csv',
            'total_rows': 1,
            'valid_rows': 1,
            'duplicate_rows': 0,
          },
          'total': 1,
          'limit': 50,
          'offset': 0,
          'items': const [],
        },
      };

    await tester.pumpWidget(_buildPage(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('wechat.csv'));
    await tester.pumpAndSettle();

    expect(find.text('导入预览'), findsOneWidget);
    expect(find.text('Batch ID：batch-001'), findsOneWidget);
    expect(api.calls.last.path, '/import/batch-001/preview');
  });

  testWidgets('ImportBatchesPage renders load errors with retry action', (
    tester,
  ) async {
    final api = _FakeApiClient()..error = StateError('batch list unavailable');

    await tester.pumpWidget(_buildPage(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('加载导入批次失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}

Widget _buildPage(ApiClient api) {
  return Provider<ApiClient>.value(
    value: api,
    child: const MaterialApp(home: ImportBatchesPage()),
  );
}

Map<String, dynamic> _batchPage({
  required int total,
  required int offset,
  required List<Map<String, dynamic>> items,
}) {
  return {
    'data': {'total': total, 'limit': 20, 'offset': offset, 'items': items},
  };
}

Map<String, dynamic> _batch({
  required String id,
  required String filename,
  required String sourceProvider,
  required String status,
  required int totalRows,
  required int validRows,
}) {
  return {
    'id': id,
    'filename': filename,
    'source_provider': sourceProvider,
    'status': status,
    'total_rows': totalRows,
    'valid_rows': validRows,
    'duplicate_rows': 0,
    'created_at': '2026-07-04T10:00:00+08:00',
  };
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost/api/v1');

  final Map<String, Map<String, dynamic>> batchResponses = {};
  final List<_ApiCall> calls = [];
  Map<String, dynamic> previewResponse = const {
    'data': {'total': 0, 'limit': 50, 'offset': 0, 'items': []},
  };
  Object? error;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final error = this.error;
    if (error != null) throw error;
    final status = params?['status'] as String?;
    final offset = params?['offset'] as int? ?? 0;
    calls.add(_ApiCall(path: path, status: status, offset: offset));
    if (path.endsWith('/preview')) return previewResponse;
    final key = status ?? '';
    return batchResponses[key] ??
        _batchPage(total: 0, offset: offset, items: const []);
  }
}

class _ApiCall {
  final String path;
  final String? status;
  final int offset;

  const _ApiCall({
    required this.path,
    required this.status,
    required this.offset,
  });
}
