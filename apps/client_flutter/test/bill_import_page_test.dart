import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/import_export/data/bill_import_file_picker.dart';
import 'package:client_flutter/features/import_export/pages/bill_import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('BillImportPage shows local mode boundary', (tester) async {
    final picker = _FakeBillImportFilePicker();
    await tester.pumpWidget(
      _buildPage(
        dataMode: LiflyDataMode.local,
        api: _FakeApiClient(),
        picker: picker,
      ),
    );

    expect(find.text('当前模式：Local Core，导入预览需要 Cloud API。'), findsOneWidget);
    expect(find.text('选择账单文件'), findsOneWidget);

    await tester.tap(find.text('选择账单文件'));
    await tester.pumpAndSettle();

    expect(picker.pickCount, 0);
  });

  testWidgets('BillImportPage uploads selected bill file and renders preview', (
    tester,
  ) async {
    final api = _FakeApiClient()
      ..multipartResponse = {
        'data': {
          'batch_id': 'batch-001',
          'source_provider': 'wechat',
          'total_rows': 3,
          'valid_rows': 2,
          'duplicate_rows': 0,
          'error_rows': 1,
          'ignored_rows': 0,
          'preview': [
            {
              'row_index': 1,
              'raw_data': {'商户': '咖啡店'},
              'parsed': {'merchant': '咖啡店', 'amount': '18.50'},
              'status': 'valid',
              'error': null,
            },
          ],
        },
      };
    final picker = _FakeBillImportFilePicker(
      selectedFile: const BillImportSelectedFile(
        name: 'wechat.csv',
        bytes: [1, 2, 3],
      ),
    );

    await tester.pumpWidget(
      _buildPage(dataMode: LiflyDataMode.api, api: api, picker: picker),
    );

    await tester.tap(find.text('选择账单文件'));
    await tester.pumpAndSettle();

    expect(api.calls.single.path, '/import/upload');
    expect(api.calls.single.filename, 'wechat.csv');
    expect(api.calls.single.params, {'provider': 'auto'});
    expect(find.text('预览已生成'), findsOneWidget);
    expect(find.text('识别来源：wechat'), findsOneWidget);
    expect(find.text('总行数：3'), findsOneWidget);
    expect(find.text('错误：1'), findsOneWidget);
    expect(find.text('咖啡店 · 18.50'), findsOneWidget);
  });

  testWidgets('BillImportPage renders upload errors as readable diagnostics', (
    tester,
  ) async {
    final api = _FakeApiClient()..error = StateError('network down');
    final picker = _FakeBillImportFilePicker(
      selectedFile: const BillImportSelectedFile(
        name: 'alipay.csv',
        bytes: [1],
      ),
    );

    await tester.pumpWidget(
      _buildPage(dataMode: LiflyDataMode.api, api: api, picker: picker),
    );

    await tester.tap(find.text('选择账单文件'));
    await tester.pumpAndSettle();

    expect(find.textContaining('上传预览失败'), findsOneWidget);
    expect(find.textContaining('network down'), findsOneWidget);
  });
}

Widget _buildPage({
  required LiflyDataMode dataMode,
  required ApiClient api,
  required BillImportFilePicker picker,
}) {
  return MultiProvider(
    providers: [
      Provider<LiflyDataMode>.value(value: dataMode),
      Provider<ApiClient>.value(value: api),
    ],
    child: MaterialApp(home: BillImportPage(filePicker: picker)),
  );
}

class _FakeBillImportFilePicker implements BillImportFilePicker {
  final BillImportSelectedFile? selectedFile;
  int pickCount = 0;

  _FakeBillImportFilePicker({this.selectedFile});

  @override
  Future<BillImportSelectedFile?> pickBillFile() async {
    pickCount += 1;
    return selectedFile;
  }
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost/api/v1');

  final List<_ApiCall> calls = [];
  Map<String, dynamic> multipartResponse = const {'data': {}};
  Object? error;

  @override
  Future<Map<String, dynamic>> postMultipartBytes(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    Map<String, dynamic>? fields,
    Map<String, dynamic>? params,
  }) async {
    calls.add(
      _ApiCall(
        path: path,
        params: params,
        fieldName: fieldName,
        bytes: bytes,
        filename: filename,
      ),
    );
    final error = this.error;
    if (error != null) throw error;
    return multipartResponse;
  }
}

class _ApiCall {
  final String path;
  final Map<String, dynamic>? params;
  final String? fieldName;
  final List<int>? bytes;
  final String? filename;

  const _ApiCall({
    required this.path,
    this.params,
    this.fieldName,
    this.bytes,
    this.filename,
  });
}
