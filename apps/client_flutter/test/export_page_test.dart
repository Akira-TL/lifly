import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/import_export/pages/export_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ExportPage disables encrypted backup in local mode', (
    tester,
  ) async {
    final api = _FakeApiClient();

    await tester.pumpWidget(
      _buildPage(dataMode: LiflyDataMode.local, api: api),
    );
    await tester.pumpAndSettle();

    await _selectEncryptedBackup(tester);

    expect(find.text('加密备份需要连接云端服务。'), findsOneWidget);
    final previewButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '生成导出预览'),
    );
    expect(previewButton.onPressed, isNull);
    expect(api.postCalls, isEmpty);
  });

  testWidgets('ExportPage generates metadata preview for selected entity', (
    tester,
  ) async {
    final api = _FakeApiClient()
      ..metadataResponse = {
        'data': {
          'contract_version': 'v0.6',
          'entity_type': 'all',
          'format': 'jsonl',
          'media_type': 'application/jsonl',
          'filename': 'lifly-export-all.jsonl',
          'size_bytes': 120,
          'checksum_sha256': 'abc123',
          'counts': {'memos': 2, 'tasks': 1},
          'preview': '{"type":"memo"}\n{"type":"task"}',
        },
      };

    await tester.pumpWidget(_buildPage(dataMode: LiflyDataMode.api, api: api));
    await tester.pumpAndSettle();
    await _selectEncryptedBackup(tester);

    await tester.tap(find.text('生成导出预览'));
    await tester.pumpAndSettle();

    expect(api.postCalls.single.path, '/export');
    expect(api.postCalls.single.data, {
      'entity_type': 'all',
      'mode': 'encrypted_backup',
    });
    expect(find.text('导出预览'), findsOneWidget);
    expect(find.text('文件名：lifly-export-all.jsonl'), findsOneWidget);
    expect(find.text('大小：120 bytes'), findsOneWidget);
    expect(find.text('导出范围：全部数据'), findsOneWidget);
    expect(find.text('文件类型：application/jsonl'), findsOneWidget);
    expect(find.text('校验值：abc123'), findsOneWidget);
    expect(find.text('格式版本：v0.6'), findsOneWidget);
    expect(find.text('备忘：2'), findsOneWidget);
    expect(find.text('任务：1'), findsOneWidget);
    expect(find.textContaining('Checksum'), findsNothing);
    expect(find.textContaining('Contract'), findsNothing);
    expect(find.textContaining('memos：'), findsNothing);
    expect(find.textContaining('{"type":"memo"}'), findsOneWidget);
  });

  testWidgets(
    'ExportPage downloads export stream and shows response metadata',
    (tester) async {
      final api = _FakeApiClient()
        ..downloadResponse = const ApiBinaryResponse(
          bytes: [1, 2, 3, 4],
          headers: {
            'content-disposition':
                'attachment; filename="lifly-export-all.jsonl"',
            'content-type': 'application/jsonl',
            'x-lifly-export-contract': 'v0.6',
            'x-lifly-export-checksum-sha256': 'def456',
            'x-lifly-export-size-bytes': '4',
          },
        );

      await tester.pumpWidget(
        _buildPage(dataMode: LiflyDataMode.api, api: api),
      );
      await tester.pumpAndSettle();
      await _selectEncryptedBackup(tester);

      await tester.tap(find.text('下载导出文件'));
      await tester.pumpAndSettle();

      expect(api.downloadCalls.single.path, '/export/stream');
      expect(api.downloadCalls.single.params, {
        'entity_type': 'all',
        'mode': 'encrypted_backup',
      });
      expect(find.text('下载完成'), findsOneWidget);
      expect(find.text('文件大小：4 bytes'), findsOneWidget);
      expect(find.text('文件名：lifly-export-all.jsonl'), findsOneWidget);
      expect(find.text('校验值：def456'), findsOneWidget);
      expect(find.text('格式版本：v0.6'), findsOneWidget);
      expect(find.textContaining('Checksum'), findsNothing);
      expect(find.textContaining('Contract'), findsNothing);
    },
  );

  testWidgets('ExportPage renders metadata and download errors', (
    tester,
  ) async {
    final api = _FakeApiClient()
      ..postError = StateError('metadata unavailable');

    await tester.pumpWidget(_buildPage(dataMode: LiflyDataMode.api, api: api));
    await tester.pumpAndSettle();
    await _selectEncryptedBackup(tester);

    await tester.tap(find.text('生成导出预览'));
    await tester.pumpAndSettle();

    expect(find.textContaining('生成导出预览失败'), findsOneWidget);
    expect(find.textContaining('metadata unavailable'), findsOneWidget);

    api
      ..postError = null
      ..downloadError = StateError('stream unavailable');

    await tester.tap(find.text('下载导出文件'));
    await tester.pumpAndSettle();

    expect(find.textContaining('下载导出文件失败'), findsOneWidget);
    expect(find.textContaining('stream unavailable'), findsOneWidget);
  });
}

Future<void> _selectEncryptedBackup(WidgetTester tester) async {
  await tester.tap(find.text('加密备份'));
  await tester.pumpAndSettle();
}

Widget _buildPage({required LiflyDataMode dataMode, required ApiClient api}) {
  return MultiProvider(
    providers: [
      Provider<LiflyDataMode>.value(value: dataMode),
      Provider<ApiClient>.value(value: api),
    ],
    child: const MaterialApp(home: ExportPage()),
  );
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost/api/v1');

  final List<_PostCall> postCalls = [];
  final List<_DownloadCall> downloadCalls = [];
  Map<String, dynamic> metadataResponse = const {'data': {}};
  ApiBinaryResponse downloadResponse = const ApiBinaryResponse(
    bytes: [],
    headers: {},
  );
  Object? postError;
  Object? downloadError;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    postCalls.add(_PostCall(path: path, data: data));
    final error = postError;
    if (error != null) throw error;
    return metadataResponse;
  }

  @override
  Future<ApiBinaryResponse> downloadBytes(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    downloadCalls.add(_DownloadCall(path: path, params: params));
    final error = downloadError;
    if (error != null) throw error;
    return downloadResponse;
  }
}

class _PostCall {
  final String path;
  final Map<String, dynamic>? data;

  const _PostCall({required this.path, required this.data});
}

class _DownloadCall {
  final String path;
  final Map<String, dynamic>? params;

  const _DownloadCall({required this.path, required this.params});
}
