import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/asset/pages/asset_list_page.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _AssetApiClient extends ApiClient {
  bool fail;

  _AssetApiClient({this.fail = false})
    : super(baseUrl: 'http://example.invalid/api/v1');

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    if (path == '/assets') {
      if (fail) throw StateError('offline');
      return {
        'success': true,
        'data': {'items': <Map<String, dynamic>>[]},
      };
    }
    return {'success': true, 'data': <String, dynamic>{}};
  }
}

Widget _host(ApiClient api) {
  return Provider<ApiClient>.value(
    value: api,
    child: const MaterialApp(home: AssetListPage()),
  );
}

void main() {
  testWidgets('asset library consumes the shared empty state', (tester) async {
    await tester.pumpWidget(_host(_AssetApiClient()));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('还没有附件'), findsOneWidget);
    expect(find.text('添加附件'), findsOneWidget);

    await tester.tap(find.text('添加附件'));
    await tester.pumpAndSettle();
    expect(find.text('上传文件'), findsOneWidget);
    expect(find.text('添加外链'), findsOneWidget);
  });

  testWidgets('asset library retries through the shared error state', (
    tester,
  ) async {
    final api = _AssetApiClient(fail: true);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('附件加载失败'), findsOneWidget);

    api.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
