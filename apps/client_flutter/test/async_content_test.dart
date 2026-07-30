import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('loading state exposes a readable progress label', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const LoadingState(message: '正在读取附件')));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在读取附件'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('page_state_loading'))),
      matchesSemantics(label: '正在读取附件', isLiveRegion: true),
    );
  });

  testWidgets('empty state presents an optional primary action', (
    tester,
  ) async {
    var created = false;
    await tester.pumpWidget(
      _host(
        EmptyState(
          icon: Icons.attach_file_outlined,
          title: '还没有附件',
          subtitle: '上传文件或登记外部链接。',
          actionLabel: '添加附件',
          onAction: () => created = true,
        ),
      ),
    );

    expect(find.text('还没有附件'), findsOneWidget);
    expect(find.text('上传文件或登记外部链接。'), findsOneWidget);
    await tester.tap(find.text('添加附件'));
    expect(created, isTrue);
  });

  testWidgets('error state keeps retry as the primary recovery action', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(ErrorState(message: '无法加载数据', onRetry: () async => retries += 1)),
    );

    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('无法加载数据'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byKey(const Key('copy_error_diagnostics')), findsOneWidget);

    await tester.tap(find.text('复制诊断'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('offline state explains local availability boundaries', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(
        OfflineState(
          title: '当前离线',
          message: '已有本地数据仍可查看，新附件将在联网后上传。',
          onRetry: () async => retries += 1,
        ),
      ),
    );

    expect(find.text('当前离线'), findsOneWidget);
    expect(find.text('已有本地数据仍可查看，新附件将在联网后上传。'), findsOneWidget);
    await tester.tap(find.text('重新连接'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('async content prioritizes offline state over stale errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AsyncContentScaffold(
          isLoading: false,
          isOffline: true,
          error: 'network error',
          isEmpty: false,
          onRefresh: () async {},
          emptyTitle: '空',
          emptySubtitle: '空',
          emptyIcon: Icons.inbox_outlined,
          child: const Text('content'),
        ),
      ),
    );

    expect(find.byType(OfflineState), findsOneWidget);
    expect(find.text('network error'), findsNothing);
    expect(find.text('content'), findsNothing);
  });

  testWidgets('page states keep a readable maximum width on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        const EmptyState(
          icon: Icons.inbox_outlined,
          title: '暂无内容',
          subtitle: '这里还没有数据。',
        ),
      ),
    );

    final size = tester.getSize(find.byKey(const Key('page_state_content')));
    expect(size.width, lessThanOrEqualTo(520));
  });
}
