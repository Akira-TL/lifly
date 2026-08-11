import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/ledger_repository.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
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
  });
}

Widget _buildApp({
  required LocalCoreBridge localCore,
  required ApiClient api,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      Provider<LocalCoreBridge>.value(value: localCore),
      Provider<LiflyDataMode>.value(value: LiflyDataMode.local),
    ],
    child: MaterialApp(home: child),
  );
}
