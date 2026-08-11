import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/lifly_semantic_colors.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:client_flutter/features/home/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ThemeData webTheme;

  setUp(() {
    webTheme = LiflyCoreTheme.tokens.buildTheme(
      Brightness.light,
      platformProfile: ThemePlatformProfile.defaults(ThemeTargetPlatform.web),
    );
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  test('Core theme exposes semantic status colors to business widgets', () {
    final semantic = webTheme.extension<LiflySemanticColors>();

    expect(semantic, isNotNull);
    expect(semantic!.critical, LiflyCoreTheme.tokens.light.colors.critical);
    expect(semantic.warning, LiflyCoreTheme.tokens.light.colors.warning);
    expect(semantic.success, LiflyCoreTheme.tokens.light.colors.success);
    expect(semantic.info, LiflyCoreTheme.tokens.light.colors.info);
    expect(semantic.neutral, LiflyCoreTheme.tokens.light.colors.neutral);
  });

  testWidgets('Web home uses the wide workbench and real overview fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(_testApp(_overview()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_focus_layout_wide')), findsOneWidget);
    expect(find.byKey(const Key('home_focus_layout_compact')), findsNothing);
    expect(find.byKey(const Key('home_focus_queue')), findsOneWidget);
    expect(find.byKey(const Key('home_focus_finance')), findsOneWidget);
    expect(find.byKey(const Key('home_focus_recent_memos')), findsOneWidget);
    expect(find.byKey(const Key('home_focus_agenda')), findsOneWidget);
    expect(find.byKey(const Key('home_focus_topbar')), findsOneWidget);
    expect(find.text('先处理这 2 件事'), findsOneWidget);
    expect(find.text('确认 Web 首页布局'), findsWidgets);
    expect(find.text('任务已逾期'), findsNothing);
    expect(find.text('需要优先处理'), findsNothing);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.textContaining('支出接近预算上限'), findsOneWidget);
    expect(find.text('更新 Web 信息架构'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('Web focus tasks complete in place with quadrant color and time bars', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    final completed = <String>[];

    await tester.pumpWidget(
      _testApp(
        _overview(attentionItems: _denseAttentionItems()),
        completeTask: (taskId) async => completed.add(taskId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_focus_queue_grid')), findsOneWidget);
    final first = find.byKey(const Key('home_focus_item_task-1'));
    final second = find.byKey(const Key('home_focus_item_task-2'));
    final third = find.byKey(const Key('home_focus_item_task-3'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(third, findsOneWidget);
    expect(
      (tester.getTopLeft(first).dy - tester.getTopLeft(second).dy).abs(),
      lessThan(1),
    );
    expect(
      (tester.getTopLeft(first).dy - tester.getTopLeft(third).dy).abs(),
      lessThan(1),
    );
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
    expect(tester.getTopLeft(second).dx, lessThan(tester.getTopLeft(third).dx));

    expect(find.text('已逾期'), findsNothing);
    expect(find.text('今天截止'), findsNothing);
    expect(find.byKey(const Key('home_focus_time_bar_task-1')), findsOneWidget);

    final quadrantColors = <Color>{
      for (final id in ['task-1', 'task-2', 'task-3', 'task-4'])
        tester
            .widget<Container>(find.byKey(Key('home_focus_quadrant_$id')))
            .color!,
    };
    expect(quadrantColors, hasLength(4));

    await tester.tap(find.byKey(const Key('home_focus_complete_task-1')));
    await tester.pumpAndSettle();
    expect(completed, ['task-1']);
  });

  testWidgets('Web schedule action stays inside the app bar boundary', (tester) async {
    tester.view.physicalSize = const Size(900, 720);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(_testApp(_overview()));
    await tester.pumpAndSettle();

    final action = find.byKey(const Key('home_schedule_action'));
    expect(action, findsOneWidget);
    final rect = tester.getRect(action);
    expect(rect.right, lessThanOrEqualTo(884));
    expect(rect.left, greaterThanOrEqualTo(0));
  });

  testWidgets('Narrow home degrades to one continuous column', (tester) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(_testApp(_overview()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_focus_layout_compact')), findsOneWidget);
    expect(find.byKey(const Key('home_focus_layout_wide')), findsNothing);
    expect(find.text('先处理这 2 件事'), findsOneWidget);
    expect(find.text('本月收支'), findsOneWidget);
    expect(find.byKey(const Key('home_focus_agenda')), findsOneWidget);
  });

  testWidgets('Phone home uses three completable focus tasks without status text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final completed = <String>[];

    await tester.pumpWidget(
      _testPhoneApp(
        _overview(attentionItems: _denseAttentionItems()),
        completeTask: (taskId) async => completed.add(taskId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('确认 Web 首页布局'), findsOneWidget);
    expect(find.text('整理抽屉'), findsNothing);
    expect(find.text('任务已逾期'), findsNothing);
    expect(find.text('已逾期'), findsNothing);
    expect(find.text('今天截止'), findsNothing);
    expect(find.byKey(const Key('home_attention_time_bar_task-1')), findsOneWidget);
    expect(find.byKey(const Key('home_attention_complete_task-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home_attention_complete_task-1')));
    await tester.pumpAndSettle();
    expect(completed, ['task-1']);
  });
}

Widget _testPhoneApp(
  HomeOverview overview, {
  Future<void> Function(String taskId)? completeTask,
}) {
  final theme = LiflyCoreTheme.tokens.buildTheme(
    Brightness.light,
    platformProfile: ThemePlatformProfile.defaults(ThemeTargetPlatform.phone),
  );
  return MaterialApp(
    theme: theme,
    home: HomePage(
      loadOverview: (_) async => overview,
      completeTask: completeTask,
    ),
  );
}

Widget _testApp(
  HomeOverview overview, {
  Future<void> Function(String taskId)? completeTask,
}) {
  final theme = LiflyCoreTheme.tokens.buildTheme(
    Brightness.light,
    platformProfile: ThemePlatformProfile.defaults(ThemeTargetPlatform.web),
  );
  return MaterialApp(
    theme: theme,
    home: HomePage(
      loadOverview: (_) async => overview,
      completeTask: completeTask,
    ),
  );
}

HomeOverview _overview({List<HomeAttentionItem>? attentionItems}) {
  final now = DateTime.utc(2026, 7, 30, 8, 30);
  return HomeOverview(
    schemaVersion: 'home_overview.v1',
    generatedAt: now,
    userTimezone: 'Asia/Shanghai',
    sourceMode: 'local',
    todayMetrics: const HomeTodayMetrics(
      memoTotal: 18,
      taskTodo: 7,
      taskTotal: 24,
      taskOverdue: 1,
      taskDueToday: 3,
    ),
    financeOverview: const HomeFinanceOverview(
      monthIncome: 8200,
      monthExpense: 1280.5,
      transactionCount: 32,
      budgetState: 'active',
      budgetAmount: 2000,
      budgetUsed: 1280.5,
      budgetProgress: 0.64,
      budgetRemaining: 719.5,
      currency: 'CNY',
      categoryBreakdown: [
        HomeFinanceCategory(
          categoryId: 'food',
          categoryName: '餐饮',
          direction: 'expense',
          amount: 620,
          ratio: 0.48,
          transactionCount: 16,
          colorToken: 'warning',
          iconToken: 'food',
        ),
        HomeFinanceCategory(
          categoryId: 'transport',
          categoryName: '交通',
          direction: 'expense',
          amount: 260,
          ratio: 0.2,
          transactionCount: 8,
          colorToken: 'info',
          iconToken: 'transport',
        ),
      ],
      insights: [
        HomeFinanceInsight(
          id: 'budget-warning',
          type: 'budget',
          level: 'warning',
          title: '支出接近预算上限',
          description: '本月预算已经使用 64%。',
        ),
      ],
    ),
    attentionItems:
        attentionItems ??
        [
          HomeAttentionItem(
            id: 'task-1',
            type: 'task_overdue',
            level: 'critical',
            quadrant: 'important_urgent',
            title: '确认 Web 首页布局',
            description: '任务已逾期',
            entityType: 'task',
            entityId: 'task-1',
            occurredAt: now.subtract(const Duration(hours: 2)),
          ),
          HomeAttentionItem(
            id: 'task-2',
            type: 'task_due_today',
            level: 'warning',
            quadrant: 'important_not_urgent',
            title: '整理导入异常记录',
            description: '今天 18:00 前完成。',
            entityType: 'task',
            entityId: 'task-2',
            occurredAt: now,
          ),
        ],
    dailyTrend: List.generate(
      7,
      (index) => HomeDailyTrendItem(
        day: now.subtract(Duration(days: 6 - index)),
        total: 80 + index * 20,
      ),
    ),
    recentActivity: [
      HomeActivityItem(
        id: 'memo-1',
        entityType: 'memo',
        entityId: 'memo-1',
        title: '更新 Web 信息架构',
        subtitle: '产品设计',
        occurredAt: now,
      ),
      HomeActivityItem(
        id: 'ledger-1',
        entityType: 'ledger_transaction',
        entityId: 'ledger-1',
        title: '食堂',
        subtitle: '餐饮',
        occurredAt: now.subtract(const Duration(hours: 1)),
        amount: 18,
        direction: 'expense',
      ),
    ],
    syncSummary: HomeSyncSummary(
      status: 'connected',
      mode: 'local',
      connected: true,
      connecting: false,
      downloading: false,
      uploading: false,
      hasSynced: true,
      lastSyncedAt: now,
      error: null,
      powerSyncConfigured: true,
      pendingAssetCount: 0,
      failedAssetCount: 0,
      syncedAssetCount: 12,
    ),
    importSummary: HomeImportSummary(
      status: 'committed',
      latestBatchId: 'batch-1',
      sourceProvider: 'wechat',
      filename: '微信支付账单.csv',
      totalRows: 120,
      validRows: 116,
      duplicateRows: 4,
      createdAt: now,
      committedAt: now,
      rolledBackAt: null,
    ),
    settingsSummary: const HomeSettingsSummary(
      status: 'ok',
      mode: 'local',
      dataMode: 'local',
      localCoreAvailable: true,
      databasePath: null,
      timezone: 'Asia/Shanghai',
      databaseConfigured: true,
      powerSyncConfigured: true,
      objectStorageConfigured: true,
    ),
  );
}

List<HomeAttentionItem> _denseAttentionItems() {
  final now = DateTime.utc(2026, 7, 30, 8, 30);
  return [
    HomeAttentionItem(
      id: 'task-1',
      type: 'task_overdue',
      level: 'critical',
      quadrant: 'important_urgent',
      title: '确认 Web 首页布局',
      description: '任务已逾期',
      entityType: 'task',
      entityId: 'task-1',
      occurredAt: now.subtract(const Duration(hours: 2)),
    ),
    HomeAttentionItem(
      id: 'task-2',
      type: 'task_focus',
      level: 'info',
      quadrant: 'important_not_urgent',
      title: '整理产品路线',
      description: null,
      entityType: 'task',
      entityId: 'task-2',
      occurredAt: now.add(const Duration(days: 2)),
    ),
    HomeAttentionItem(
      id: 'task-3',
      type: 'task_due_today',
      level: 'warning',
      quadrant: 'not_important_urgent',
      title: '回复临时消息',
      description: null,
      entityType: 'task',
      entityId: 'task-3',
      occurredAt: now.add(const Duration(hours: 3)),
    ),
    HomeAttentionItem(
      id: 'task-4',
      type: 'task_focus',
      level: 'normal',
      quadrant: 'not_important_not_urgent',
      title: '整理抽屉',
      description: null,
      entityType: 'task',
      entityId: 'task-4',
      occurredAt: now.add(const Duration(days: 5)),
    ),
    HomeAttentionItem(
      id: 'task-5',
      type: 'task_focus',
      level: 'info',
      quadrant: 'important_not_urgent',
      title: '检查下周计划',
      description: null,
      entityType: 'task',
      entityId: 'task-5',
      occurredAt: now.add(const Duration(days: 3)),
    ),
    HomeAttentionItem(
      id: 'task-6',
      type: 'task_focus',
      level: 'normal',
      quadrant: 'not_important_not_urgent',
      title: '整理下载目录',
      description: null,
      entityType: 'task',
      entityId: 'task-6',
      occurredAt: now.add(const Duration(days: 6)),
    ),
  ];
}
