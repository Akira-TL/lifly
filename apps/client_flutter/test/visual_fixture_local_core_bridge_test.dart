import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/features/memo/pages/memo_list_page.dart';
import 'package:client_flutter/features/task/pages/task_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 15, 0);
  final context = LocalCoreContext.flutterUser(now: now);

  test('visual fixture bridge provides dense cross-feature data', () async {
    final bridge = VisualFixtureLocalCoreBridge(now: now);

    final memos = await bridge.searchMemos({'q': '', 'limit': 100}, context);
    final tasks = await bridge.listTasks({'group': 'all', 'limit': 100}, context);
    final transactions = await bridge.searchExpenses(
      {'q': '', 'limit': 100},
      context,
    );
    final sessions = await bridge.listCaptureSessions(
      {'status': 'active', 'limit': 100, 'offset': 0},
      context,
    );

    expect(memos, hasLength(18));
    expect(memos.map((item) => item.type).toSet(), containsAll(<String>{
      'memo',
      'journal',
      'clip',
      'doc',
    }));
    expect(memos.any((item) => item.title != null && item.title!.length > 24), isTrue);
    expect(memos.any((item) => item.tags.length >= 3), isTrue);

    expect(tasks, hasLength(15));
    expect(tasks.map((item) => item.taskStatus).toSet(), containsAll(<String>{
      'todo',
      'doing',
      'done',
    }));
    expect(
      tasks.any(
        (item) =>
            item.taskStatus != 'done' &&
            item.dueAt != null &&
            item.dueAt!.isBefore(now),
      ),
      isTrue,
    );
    expect(
      tasks.any(
        (item) =>
            item.dueAt != null &&
            item.dueAt!.year == now.year &&
            item.dueAt!.month == now.month &&
            item.dueAt!.day == now.day,
      ),
      isTrue,
    );

    expect(transactions, hasLength(20));
    expect(
      transactions.map((item) => item.direction).toSet(),
      containsAll(<String>{'expense', 'income'}),
    );
    expect(transactions.any((item) => item.amount >= 10000), isTrue);
    expect(transactions.any((item) => item.amount < 10), isTrue);

    expect(sessions, hasLength(8));
    expect(sessions.any((item) => item.turns.length >= 4), isTrue);
    expect(sessions.any((item) => item.committed), isTrue);
  });

  test('visual fixture bridge resets by recreating the in-memory bridge', () async {
    final first = VisualFixtureLocalCoreBridge(now: now);
    await first.createMemo(
      {
        'type': 'memo',
        'title': '临时视觉测试记录',
        'content_markdown': '只存在于这一份内存数据中。',
        'tags': ['fixture'],
      },
      context,
    );
    expect(
      await first.searchMemos({'q': '', 'limit': 100}, context),
      hasLength(19),
    );

    final fresh = VisualFixtureLocalCoreBridge(now: now);
    expect(
      await fresh.searchMemos({'q': '', 'limit': 100}, context),
      hasLength(18),
    );
  });

  testWidgets('visual fixture bridge renders dense memo list', (tester) async {
    final bridge = VisualFixtureLocalCoreBridge(now: now);
    await tester.pumpWidget(_fixtureApp(bridge, const MemoListPage()));
    await tester.pumpAndSettle();

    expect(find.text('本周需要处理的杂事'), findsOneWidget);
    expect(find.text('Lifly 首页信息密度与跨端布局调整记录'), findsOneWidget);
  });

  testWidgets('visual fixture bridge renders task states', (tester) async {
    final bridge = VisualFixtureLocalCoreBridge(now: now);
    await tester.pumpWidget(_fixtureApp(bridge, const TaskListPage()));
    await tester.pumpAndSettle();

    expect(find.text('提交本周项目进度总结'), findsOneWidget);
    expect(find.text('回复积压的三封重要邮件'), findsOneWidget);
  });

  test('visual fixture bridge drives a populated home overview', () async {
    final bridge = VisualFixtureLocalCoreBridge(now: now);

    final overview = await bridge.getHomeOverview(
      {'period': 'current_month', 'source_mode': 'visual_fixture'},
      context,
    );

    expect(overview.sourceMode, 'visual_fixture');
    expect(overview.todayMetrics.memoTotal, 18);
    expect(overview.todayMetrics.taskDueToday, greaterThan(0));
    expect(overview.todayMetrics.taskOverdue, greaterThan(0));
    expect(overview.attentionItems, isNotEmpty);
    expect(overview.recentActivity, isNotEmpty);
    expect(overview.financeOverview.monthExpense, greaterThan(0));
    expect(overview.financeOverview.monthIncome, greaterThan(0));
  });
}

Widget _fixtureApp(LocalCoreBridge bridge, Widget home) {
  return MultiProvider(
    providers: [
      Provider<LiflyDataMode>.value(value: LiflyDataMode.local),
      Provider<ApiClient>(
        create: (_) => ApiClient(baseUrl: 'http://127.0.0.1:8310/api/v1'),
      ),
      Provider<LocalCoreBridge>.value(value: bridge),
    ],
    child: MaterialApp(home: home),
  );
}
