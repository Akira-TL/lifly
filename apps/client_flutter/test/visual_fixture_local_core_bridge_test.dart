import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/features/ledger/pages/ledger_list_page.dart';
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

  testWidgets('visual fixture bridge renders a compact memo list', (tester) async {
    await _usePhoneViewport(tester);
    final bridge = VisualFixtureLocalCoreBridge(now: now);
    await tester.pumpWidget(_fixtureApp(bridge, const MemoListPage()));
    await tester.pumpAndSettle();

    final first = find.text('本周需要处理的杂事');
    final second = find.text('Lifly 首页信息密度与跨端布局调整记录');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(find.byKey(const Key('memo_inline_search')), findsNothing);
    expect(find.byTooltip('搜索备忘'), findsOneWidget);
    expect(
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).isExtended,
      isFalse,
    );
    final timestamp = find.byKey(const Key('memo_timestamp_visual_memo_02'));
    expect(timestamp, findsOneWidget);
    expect(tester.getRect(timestamp).right, lessThanOrEqualTo(374));
    expect(tester.getTopLeft(second).dy - tester.getTopLeft(first).dy, lessThan(90));

    await tester.tap(find.byTooltip('搜索备忘'));
    await tester.pump();
    expect(find.byKey(const Key('memo_inline_search')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('memo_inline_search')), findsNothing);
    expect(find.text('备忘录'), findsOneWidget);
  });

  testWidgets('visual fixture bridge renders localized compact task states', (
    tester,
  ) async {
    await _usePhoneViewport(tester);
    final bridge = VisualFixtureLocalCoreBridge(now: now);
    await tester.pumpWidget(_fixtureApp(bridge, const TaskListPage()));
    await tester.pumpAndSettle();

    final first = find.text('提交本周项目进度总结');
    final second = find.text('确认明天上午的体检预约和需要空腹的项目');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(second).dy - tester.getTopLeft(first).dy, lessThan(90));
    expect(find.textContaining('urgent'), findsNothing);
    expect(find.textContaining('紧急'), findsWidgets);
    expect(
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).isExtended,
      isFalse,
    );
    final dueTime = find.byKey(const Key('task_due_visual_task_02'));
    expect(dueTime, findsOneWidget);
    expect(tester.getRect(dueTime).right, lessThan(360));
  });

  testWidgets('visual fixture bridge renders compact ledger rows without source diagnostics', (
    tester,
  ) async {
    await _usePhoneViewport(tester);
    final bridge = VisualFixtureLocalCoreBridge(now: now);
    await tester.pumpWidget(_fixtureApp(bridge, const LedgerListPage()));
    await tester.pumpAndSettle();

    final first = find.text('社区咖啡店');
    final second = find.text('地铁');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(second).dy - tester.getTopLeft(first).dy, lessThan(74));
    expect(find.textContaining('local'), findsNothing);
    expect(
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).isExtended,
      isFalse,
    );
    final occurredAt = find.byKey(const Key('ledger_time_visual_tx_01'));
    expect(occurredAt, findsOneWidget);
    expect(tester.getRect(occurredAt).right, lessThan(360));
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
    expect(overview.attentionItems.length, greaterThanOrEqualTo(6));
    expect(
      overview.attentionItems.map((item) => item.quadrant).toSet(),
      containsAll(<String>{
        'urgent_important',
        'urgent_not_important',
        'not_urgent_important',
        'not_urgent_not_important',
      }),
    );
    expect(
      overview.attentionItems.every((item) => item.urgencyWindowSeconds >= 0),
      isTrue,
    );
    expect(overview.recentActivity, isNotEmpty);
    expect(overview.financeOverview.monthExpense, greaterThan(0));
    expect(overview.financeOverview.monthIncome, greaterThan(0));
    expect(overview.financeOverview.categoryBreakdown, isNotEmpty);
    expect(
      overview.financeOverview.categoryBreakdown.first.categoryName,
      isNot('未分类'),
    );
  });
}

Future<void> _usePhoneViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
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
