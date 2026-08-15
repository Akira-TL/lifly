import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/asset_repository.dart';
import 'package:client_flutter/domain/entities/asset.dart';
import 'package:client_flutter/features/asset/pages/asset_list_page.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _AssetApiClient extends ApiClient {
  bool fail;
  bool failPosts;

  _AssetApiClient({this.fail = false, this.failPosts = false})
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

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    if (failPosts) throw StateError('storage gateway leaked');
    return {
      'success': true,
      'data': {
        'asset': {
          'id': 'asset-link-1',
          'kind': 'external_url',
          'asset_type': 'link',
          'status': 'active',
          'external_url': data?['external_url'],
          'title': data?['title'],
          'created_at': DateTime.utc(2026, 8, 15).toIso8601String(),
          'updated_at': DateTime.utc(2026, 8, 15).toIso8601String(),
        },
      },
    };
  }
}

class _AssetTestRepository extends AssetRepository {
  _AssetTestRepository(this.client) : super(client);

  final _AssetApiClient client;

  @override
  Future<List<Asset>> list({
    int limit = 20,
    int offset = 0,
    String? kind,
    String? assetType,
  }) async {
    if (client.fail) throw StateError('offline');
    return const [];
  }

  @override
  Future<Asset> registerExternalUrl({
    required String externalUrl,
    String? externalProvider,
    String assetType = 'link',
    String? title,
    String? previewUrl,
  }) async {
    if (client.failPosts) throw StateError('storage gateway leaked');
    return Asset(
      id: 'asset-link-1',
      userId: 'account-1',
      kind: 'external',
      assetType: assetType,
      status: 'active',
      externalUrl: externalUrl,
      title: title,
      createdAt: DateTime.utc(2026, 8, 15),
      updatedAt: DateTime.utc(2026, 8, 15),
    );
  }
}

Widget _host(_AssetApiClient api) {
  return Provider<ApiClient>.value(
    value: api,
    child: MaterialApp(
      home: AssetListPage(repository: _AssetTestRepository(api)),
    ),
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

  testWidgets('external link validates input and hides submit failures', (
    tester,
  ) async {
    final api = _AssetApiClient(failPosts: true);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加外链'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请输入链接地址'), findsOneWidget);

    final urlField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'URL',
    );
    await tester.enterText(urlField, 'https://example.com/article');
    await tester.pump();
    expect(find.text('请输入链接地址'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('添加外链失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('storage gateway leaked'), findsNothing);
  });

  testWidgets('asset library retries through the shared error state', (
    tester,
  ) async {
    final api = _AssetApiClient(fail: true);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('加载附件失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing);

    api.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
