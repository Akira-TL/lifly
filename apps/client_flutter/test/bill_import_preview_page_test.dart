import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/import_export/pages/bill_import_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'BillImportPreviewPage loads preview rows and filters by status',
    (tester) async {
      final api = _FakeApiClient()
        ..pageResponses[0] = _previewPage(
          total: 2,
          offset: 0,
          items: [
            _row(
              id: 'row-1',
              rowIndex: 1,
              status: 'pending',
              merchant: '咖啡店',
              amount: '18.50',
              occurredAt: '2026-07-04T10:00:00+08:00',
            ),
            _row(
              id: 'row-2',
              rowIndex: 2,
              status: 'error',
              merchant: null,
              amount: null,
              occurredAt: null,
              errorMessage: 'Invalid amount',
            ),
          ],
        );

      await tester.pumpWidget(_buildPage(api));
      await tester.pumpAndSettle();

      expect(find.text('导入预览'), findsOneWidget);
      expect(find.text('Batch ID：batch-001'), findsOneWidget);
      expect(find.text('待导入（1）'), findsOneWidget);
      expect(find.text('错误（1）'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('咖啡店 · 18.50'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('咖啡店 · 18.50'), findsOneWidget);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('错误（1）'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('未解析商户 · -'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('咖啡店 · 18.50'), findsNothing);
      expect(find.text('未解析商户 · -'), findsOneWidget);
    },
  );

  testWidgets('BillImportPreviewPage loads more rows by pagination', (
    tester,
  ) async {
    final api = _FakeApiClient()
      ..pageResponses[0] = _previewPage(
        total: 2,
        offset: 0,
        items: [
          _row(
            id: 'row-1',
            rowIndex: 1,
            status: 'pending',
            merchant: '第一行',
            amount: '1.00',
            occurredAt: '2026-07-04T10:00:00+08:00',
          ),
        ],
      )
      ..pageResponses[1] = _previewPage(
        total: 2,
        offset: 1,
        items: [
          _row(
            id: 'row-2',
            rowIndex: 2,
            status: 'duplicate',
            merchant: '第二行',
            amount: '2.00',
            occurredAt: '2026-07-04T11:00:00+08:00',
          ),
        ],
      );

    await tester.pumpWidget(_buildPage(api));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('第一行 · 1.00'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('第一行 · 1.00'), findsOneWidget);
    expect(find.text('第二行 · 2.00'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('加载更多'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(api.calls.map((call) => call.offset), [0, 1]);
    expect(find.text('第二行 · 2.00'), findsOneWidget);
  });

  testWidgets('BillImportPreviewPage renders load failures with retry action', (
    tester,
  ) async {
    final api = _FakeApiClient()..error = StateError('preview unavailable');

    await tester.pumpWidget(_buildPage(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('加载预览失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('BillImportPreviewPage confirms commit and renders result', (
    tester,
  ) async {
    final api = _FakeApiClient()
      ..pageResponses[0] = _previewPage(
        total: 1,
        offset: 0,
        items: [
          _row(
            id: 'row-1',
            rowIndex: 1,
            status: 'pending',
            merchant: '咖啡店',
            amount: '18.50',
            occurredAt: '2026-07-04T10:00:00+08:00',
          ),
        ],
      )
      ..commitResponse = {
        'data': {
          'batch_id': 'batch-001',
          'source_provider': 'wechat',
          'imported': 1,
          'duplicates': 0,
          'errors': 0,
          'skipped': 0,
          'status': 'committed',
        },
      };

    await tester.pumpWidget(_buildPage(api));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '提交导入'));
    await tester.pumpAndSettle();

    expect(find.text('确认提交导入？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
    await tester.pumpAndSettle();

    expect(api.postPaths, ['/import/batch-001/commit']);
    expect(find.text('提交结果：已提交'), findsOneWidget);
    expect(find.text('已导入：1'), findsOneWidget);
  });

  testWidgets('BillImportPreviewPage renders duplicate commit errors', (
    tester,
  ) async {
    final api = _FakeApiClient()
      ..pageResponses[0] = _previewPage(total: 0, offset: 0, items: const [])
      ..commitError = StateError('already committed');

    await tester.pumpWidget(_buildPage(api));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '提交导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
    await tester.pumpAndSettle();

    expect(find.textContaining('提交导入失败'), findsOneWidget);
    expect(find.textContaining('already committed'), findsOneWidget);
  });
}

Widget _buildPage(ApiClient api) {
  return Provider<ApiClient>.value(
    value: api,
    child: const MaterialApp(home: BillImportPreviewPage(batchId: 'batch-001')),
  );
}

Map<String, dynamic> _previewPage({
  required int total,
  required int offset,
  required List<Map<String, dynamic>> items,
}) {
  return {
    'data': {
      'batch': {
        'id': 'batch-001',
        'status': 'preview',
        'filename': 'wechat.csv',
        'total_rows': total,
        'valid_rows': 1,
        'duplicate_rows': 1,
      },
      'total': total,
      'limit': 50,
      'offset': offset,
      'items': items,
    },
  };
}

Map<String, dynamic> _row({
  required String id,
  required int rowIndex,
  required String status,
  required String? merchant,
  required String? amount,
  required String? occurredAt,
  String? errorMessage,
}) {
  return {
    'id': id,
    'row_index': rowIndex,
    'raw_data': {'row': rowIndex},
    'parsed_data': merchant == null && amount == null && occurredAt == null
        ? null
        : {
            'direction': 'expense',
            'amount': amount,
            'merchant': merchant,
            'occurred_at': occurredAt,
            'note': '测试备注',
          },
    'status': status,
    'error_message': errorMessage,
  };
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost/api/v1');

  final Map<int, Map<String, dynamic>> pageResponses = {};
  final List<_ApiCall> calls = [];
  final List<String> postPaths = [];
  Map<String, dynamic> commitResponse = const {
    'data': {
      'batch_id': 'batch-001',
      'source_provider': 'wechat',
      'imported': 0,
      'duplicates': 0,
      'errors': 0,
      'skipped': 0,
      'status': 'committed',
    },
  };
  Object? error;
  Object? commitError;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final offset = params?['offset'] as int? ?? 0;
    calls.add(_ApiCall(path: path, offset: offset));
    final error = this.error;
    if (error != null) throw error;
    return pageResponses[offset] ??
        _previewPage(total: 0, offset: offset, items: const []);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    postPaths.add(path);
    final error = commitError;
    if (error != null) throw error;
    return commitResponse;
  }
}

class _ApiCall {
  final String path;
  final int offset;

  const _ApiCall({required this.path, required this.offset});
}
