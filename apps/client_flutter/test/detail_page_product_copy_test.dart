import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/ledger_repository.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
import 'package:client_flutter/domain/entities/memo.dart';
import 'package:client_flutter/features/ledger/pages/ledger_detail_page.dart';
import 'package:client_flutter/features/memo/pages/memo_detail_page.dart';
import 'package:client_flutter/features/task/pages/task_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late ApiClient api;
  late FakeLocalCoreBridge localCore;

  setUp(() {
    api = ApiClient(baseUrl: 'http://localhost/api/v1');
    localCore = FakeLocalCoreBridge();
  });

  testWidgets('memo detail keeps metadata product-facing', (tester) async {
    final repo = MemoRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );
    final memo = await repo.create({
      'type': 'journal',
      'title': '今天的记录',
      'content_markdown': '正文',
      'tags': ['生活'],
    });

    await tester.pumpWidget(
      _buildApp(
        localCore: localCore,
        api: api,
        child: MemoDetailPage(memoId: memo.id, initialMemo: memo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('日记 · 正常'), findsOneWidget);
    expect(find.textContaining('journal'), findsNothing);
    expect(find.textContaining('active'), findsNothing);
    expect(find.byTooltip('编辑备忘'), findsOneWidget);
    expect(find.byTooltip('删除备忘'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑备忘'));
    await tester.pumpAndSettle();
    await tester.enterText(_textField('标题'), '');
    await tester.enterText(_textField('内容'), '');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请输入标题或内容'), findsOneWidget);
    expect(find.text('编辑备忘'), findsOneWidget);

    await tester.enterText(_textField('标题'), '只有标题也可以保存');
    await tester.pump();
    expect(find.text('请输入标题或内容'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('只有标题也可以保存'), findsOneWidget);

    final addLinkButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '添加外链'),
    );
    expect(addLinkButton.onPressed, isNull);
    expect(find.textContaining('附件引用需连接云端服务'), findsOneWidget);
  });

  testWidgets('cloud memo external link validates the URL inline', (
    tester,
  ) async {
    final memo = Memo(
      id: 'memo-cloud-1',
      type: 'memo',
      title: '云端备忘',
      contentMarkdown: '正文',
      tags: const [],
      status: 'active',
      createdAt: DateTime.utc(2026, 8, 11, 8),
      updatedAt: DateTime.utc(2026, 8, 11, 8),
    );
    final cloudApi = _MemoDetailApiClient(memo);

    await tester.pumpWidget(
      _buildApp(
        localCore: localCore,
        api: cloudApi,
        dataMode: LiflyDataMode.api,
        child: MemoDetailPage(memoId: memo.id, initialMemo: memo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加外链'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请输入链接地址'), findsOneWidget);

    await tester.enterText(_textField('URL'), 'https://example.com/article');
    await tester.pump();
    expect(find.text('请输入链接地址'), findsNothing);
  });

  testWidgets('memo detail hides implementation errors from users', (
    tester,
  ) async {
    final memo = Memo(
      id: 'memo-cloud-error-1',
      type: 'memo',
      title: '会失败的备忘',
      contentMarkdown: '正文',
      tags: const [],
      status: 'active',
      createdAt: DateTime.utc(2026, 8, 15, 8),
      updatedAt: DateTime.utc(2026, 8, 15, 8),
    );
    final cloudApi = _MemoDetailApiClient(memo, failUpdates: true);

    await tester.pumpWidget(
      _buildApp(
        localCore: localCore,
        api: cloudApi,
        dataMode: LiflyDataMode.api,
        child: MemoDetailPage(memoId: memo.id, initialMemo: memo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑备忘'));
    await tester.pumpAndSettle();
    await tester.enterText(_textField('标题'), '更新后的标题');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('更新备忘失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('PowerSync internal transport'), findsNothing);
  });

  testWidgets('task detail localizes status and priority', (tester) async {
    final repo = TaskRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );
    final created = await repo.create({'title': '提交报告', 'priority': 'urgent'});
    final task = await repo.update(created.id, {
      'priority': 'urgent',
      'task_status': 'doing',
    });

    await tester.pumpWidget(
      _buildApp(
        localCore: localCore,
        api: api,
        child: TaskDetailPage(taskId: task.id, initialTask: task),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('紧急'), findsOneWidget);
    expect(find.text('doing'), findsNothing);
    expect(find.text('urgent'), findsNothing);
    expect(find.byTooltip('编辑任务'), findsOneWidget);
    expect(find.byTooltip('删除任务'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑任务'));
    await tester.pumpAndSettle();
    await tester.enterText(_textField('标题'), '');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请输入任务标题'), findsOneWidget);
    expect(find.text('编辑任务'), findsOneWidget);

    await tester.enterText(_textField('标题'), '修正后的任务标题');
    await tester.pump();
    expect(find.text('请输入任务标题'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('修正后的任务标题'), findsOneWidget);
  });

  testWidgets('ledger detail localizes direction and source', (tester) async {
    final repo = LedgerRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );
    final transaction = await repo.create({
      'direction': 'expense',
      'amount': 28.6,
      'merchant': '咖啡店',
    });

    await tester.pumpWidget(
      _buildApp(
        localCore: localCore,
        api: api,
        child: LedgerDetailPage(
          transactionId: transaction.id,
          initialTransaction: transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('支出'), findsOneWidget);
    expect(find.text('本地记录'), findsOneWidget);
    expect(find.text('expense'), findsNothing);
    expect(find.text('local'), findsNothing);
    expect(find.byTooltip('编辑账单'), findsOneWidget);
    expect(find.byTooltip('删除账单'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑账单'));
    await tester.pumpAndSettle();
    await tester.enterText(_textField('金额'), '0');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请输入大于 0 的金额'), findsOneWidget);
    expect(find.text('编辑账单'), findsOneWidget);

    await tester.enterText(_textField('金额'), '36.50');
    await tester.pump();
    expect(find.text('请输入大于 0 的金额'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('36.50'), findsOneWidget);
  });
}

Finder _textField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Widget _buildApp({
  required LocalCoreBridge localCore,
  required ApiClient api,
  LiflyDataMode dataMode = LiflyDataMode.local,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      Provider<LocalCoreBridge>.value(value: localCore),
      Provider<LiflyDataMode>.value(value: dataMode),
    ],
    child: MaterialApp(home: child),
  );
}

class _MemoDetailApiClient extends ApiClient {
  _MemoDetailApiClient(this.memo, {this.failUpdates = false})
    : super(baseUrl: 'http://localhost/api/v1');

  final Memo memo;
  final bool failUpdates;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    return {
      'data': {
        'id': memo.id,
        'type': memo.type,
        'title': memo.title,
        'content_markdown': memo.contentMarkdown,
        'tags': memo.tags,
        'mood': memo.mood,
        'status': memo.status,
        'created_at': memo.createdAt.toIso8601String(),
        'updated_at': memo.updatedAt.toIso8601String(),
        'assets': const [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    if (failUpdates) {
      throw StateError('PowerSync internal transport leaked');
    }
    return get(path);
  }
}
