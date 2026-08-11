import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/repositories/home_overview_repository.dart';
import 'package:client_flutter/data/repositories/ledger_repository.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ApiClient api;
  late FakeLocalCoreBridge localCore;

  setUp(() {
    api = ApiClient(baseUrl: 'http://localhost/api/v1');
    localCore = FakeLocalCoreBridge();
  });

  test('MemoRepository uses Local Core in local mode', () async {
    final repo = MemoRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );

    final memo = await repo.create({
      'type': 'memo',
      'title': 'Local memo',
      'content_markdown': 'stored locally',
      'tags': ['local'],
      'mood': '开心',
    });
    final updated = await repo.update(memo.id, {'mood': '平静'});
    final reloaded = await repo.get(memo.id);
    final cleared = await repo.update(memo.id, {'mood': null});
    final afterClear = await repo.get(memo.id);
    final page = await repo.listPage(q: 'stored locally');

    expect(memo.id, 'local_memo_0001');
    expect(memo.mood, '开心');
    expect(updated.mood, '平静');
    expect(reloaded.mood, '平静');
    expect(cleared.mood, isNull);
    expect(afterClear.mood, isNull);
    expect(page.items.map((item) => item.id), contains(memo.id));
  });

  test('TaskRepository uses Local Core in local mode', () async {
    final repo = TaskRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );

    final task = await repo.create({'title': 'Local task'});
    final completed = await repo.complete(task.id);
    final page = await repo.listPage(taskStatus: 'done');

    expect(completed.taskStatus, 'done');
    expect(page.items.map((item) => item.id), contains(task.id));

    await repo.delete(task.id);
    expect(
      (await repo.listPage(taskStatus: 'done')).items.map((item) => item.id),
      isNot(contains(task.id)),
    );
    final restored = await repo.restore(task.id);
    expect(restored.taskStatus, 'done');
    expect(
      (await repo.listPage(taskStatus: 'done')).items.map((item) => item.id),
      contains(task.id),
    );
  });

  test('TaskRepository restores through the trash endpoint in api mode', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
    final requests = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add('${options.method} ${options.path}');
          if (options.method == 'POST') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'entity_type': 'task',
                    'entity_id': 'cloud-task',
                    'status': 'active',
                    'revision': 3,
                  },
                },
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'id': 'cloud-task',
                  'title': '云端恢复任务',
                  'description': null,
                  'due_at': null,
                  'remind_at': null,
                  'priority': 'normal',
                  'task_status': 'todo',
                  'completed_at': null,
                  'created_at': '2026-08-11T05:00:00Z',
                },
              },
            ),
          );
        },
      ),
    );
    final repo = TaskRepository(
      ApiClient(baseUrl: 'http://localhost/api/v1', dio: dio),
      localCore: localCore,
      dataMode: LiflyDataMode.api,
    );

    final restored = await repo.restore('cloud-task');

    expect(restored.title, '云端恢复任务');
    expect(requests, [
      'POST /trash/task/cloud-task/restore',
      'GET /tasks/cloud-task',
    ]);
  });

  test('TaskRepository handles reminder strategy boundaries locally', () async {
    final repo = TaskRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );
    final task = await repo.create({
      'title': '需要准备的任务',
      'due_at': DateTime.now()
          .toUtc()
          .add(const Duration(days: 2))
          .toIso8601String(),
      'priority': 'normal',
    });

    final generated = await repo.reminderStrategy(task.id);
    expect(generated, isNotNull);
    expect(generated!['source'], 'ai');
    final warningPageBefore = await repo.listPage(group: 'warning');
    expect(warningPageBefore.items.map((item) => item.id), contains(task.id));

    final confirmed = await repo.confirmReminderStrategy(task.id, {
      'warning_level': 'critical',
      'warning_reason': '需要提前准备材料',
      'preparation_window_days': 2,
      'ai_suggested_remind_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'source': 'ai',
    });
    final urgentPage = await repo.listPage(group: 'urgent');

    expect(confirmed['strategy_status'], 'confirmed');
    expect(confirmed['warning_level'], 'critical');
    expect(urgentPage.items.map((item) => item.id), contains(task.id));

    final dismissed = await repo.dismissReminderStrategy(task.id, {
      'strategy_id': confirmed['id'],
    });
    expect(dismissed['strategy_status'], 'dismissed');
    expect(await repo.reminderStrategy(task.id), isNull);
  });

  test('TaskRepository manages reminder dispatch lifecycle locally', () async {
    final repo = TaskRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );
    final now = DateTime.now().toUtc();
    final task = await repo.create({
      'title': '本地派发任务',
      'description': '验证 repository 提醒状态接口',
      'due_at': now.add(const Duration(hours: 2)).toIso8601String(),
    });
    await repo.confirmReminderStrategy(task.id, {
      'warning_level': 'warning',
      'ai_suggested_remind_at': now.toIso8601String(),
    });

    final claimed = await repo.claimDueReminders(
      now: now.add(const Duration(seconds: 1)),
    );
    expect(claimed, hasLength(1));
    expect(claimed.single['attempt_count'], 1);
    final reminderId = claimed.single['id'] as String;
    final dispatchToken = claimed.single['dispatch_token'] as String;

    final failed = await repo.markReminderFailed(
      reminderId,
      dispatchToken: dispatchToken,
      error: 'temporary notification failure',
      retryAfterSeconds: 0,
    );
    expect(failed['reminder_status'], 'failed');
    expect(failed['last_error'], 'temporary notification failure');

    final retried = await repo.retryReminder(reminderId);
    expect(retried['reminder_status'], 'pending');
    expect(retried['attempt_count'], 0);

    final cancelled = await repo.cancelReminder(reminderId);
    expect(cancelled['reminder_status'], 'cancelled');
    final cancelledItems = await repo.reminders(status: 'cancelled');
    expect(cancelledItems.map((item) => item['id']), contains(reminderId));
  });

  test(
    'MemoRepository handles local classifications and tag summary',
    () async {
      final memoRepo = MemoRepository(
        api,
        localCore: localCore,
        dataMode: LiflyDataMode.local,
      );
      final memo = await memoRepo.create({
        'type': 'memo',
        'title': '分类备忘',
        'content_markdown': '用于测试分类边界',
      });

      final confirmed = await memoRepo.confirmClassification(memo.id, {
        'tag': '读书',
        'source': 'ai',
        'confidence': 0.8,
      });
      await memoRepo.rejectClassification(memo.id, {'tag': '丢弃'});
      final classifications = await memoRepo.classifications(memo.id);
      final tags = await memoRepo.tagSummary();

      expect(confirmed['status'], 'confirmed');
      expect(classifications.length, greaterThanOrEqualTo(2));
      expect(classifications.map((item) => item['tag']), contains('读书'));
      expect(tags.map((item) => item['tag']), contains('读书'));
      final readingTag = tags.firstWhere((item) => item['tag'] == '读书');
      expect(readingTag['confirmed_count'], 1);
    },
  );

  test('LedgerRepository uses Local Core in local mode', () async {
    final repo = LedgerRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );

    final tx = await repo.create({
      'direction': 'expense',
      'amount': 12.5,
      'merchant': 'Local Merchant',
    });
    final updated = await repo.update(tx.id, {
      'direction': 'expense',
      'amount': 18.75,
      'merchant': 'Updated Local Merchant',
      'note': 'edited from detail page',
      'occurred_at': tx.occurredAt.toUtc().toIso8601String(),
    });
    final reloaded = await repo.get(tx.id);
    final summary = await repo.summary();

    expect(tx.id, 'local_tx_0001');
    expect(updated.amount, 18.75);
    expect(updated.merchant, 'Updated Local Merchant');
    expect(reloaded.amount, 18.75);
    expect(reloaded.note, 'edited from detail page');
    expect(summary['expense_total'], 18.75);
    expect(summary['transaction_count'], 1);
  });

  test('LedgerRepository manages budgets through Local Core', () async {
    final repo = LedgerRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );
    final now = DateTime.now().toUtc();
    final period =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

    final overall = await repo.createBudget({
      'period_key': period,
      'amount': 3000,
      'alert_threshold': 0.8,
    });
    final category = await repo.createBudget({
      'period_key': period,
      'category_id': 'food',
      'amount': 1200,
    });
    final budgets = await repo.listBudgets(period: period);

    expect(overall.isOverall, isTrue);
    expect(category.categoryId, 'food');
    expect(budgets, hasLength(2));
    expect(
      () => repo.createBudget({'period_key': period, 'amount': 1000}),
      throwsStateError,
    );

    final updated = await repo.updateBudget(overall.id, {'amount': 3500});
    expect(updated.amount, 3500);
    expect(updated.revision, 2);

    final deleted = await repo.deleteBudget(category.id);
    expect(deleted.status, 'deleted');
    expect(await repo.listBudgets(period: period), hasLength(1));
  });

  test('LedgerRepository prefers cloud budget reads', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
    String? requestedPath;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedPath = options.path;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': [
                  {
                    'id': 'cloud-budget',
                    'period_type': 'month',
                    'period_key': '2026-07',
                    'category_id': null,
                    'category_name': null,
                    'amount': 5000,
                    'currency': 'CNY',
                    'alert_threshold': 0.8,
                    'status': 'active',
                    'revision': 3,
                    'created_at': '2026-07-01T00:00:00Z',
                    'updated_at': '2026-07-08T00:00:00Z',
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    final repo = LedgerRepository(
      ApiClient(baseUrl: 'http://localhost/api/v1', dio: dio),
      localCore: localCore,
      dataMode: LiflyDataMode.api,
    );

    final budgets = await repo.listBudgets(period: '2026-07');

    expect(requestedPath, '/ledger/budgets');
    expect(budgets.single.id, 'cloud-budget');
    expect(budgets.single.amount, 5000);
    expect(budgets.single.revision, 3);
  });

  test('LedgerRepository falls back to local budget reads', () async {
    final now = DateTime.now().toUtc();
    final period =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final localRepo = LedgerRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );
    await localRepo.createBudget({'period_key': period, 'amount': 2600});

    final failingDio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
    failingDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'offline',
            ),
          );
        },
      ),
    );
    final repo = LedgerRepository(
      ApiClient(baseUrl: 'http://localhost/api/v1', dio: failingDio),
      localCore: localCore,
      dataMode: LiflyDataMode.api,
    );

    final budgets = await repo.listBudgets(period: period);

    expect(budgets.single.amount, 2600);
  });

  test(
    'HomeOverviewRepository computes overview from Local Core in local mode',
    () async {
      final memoRepo = MemoRepository(
        api,
        localCore: localCore,
        dataMode: LiflyDataMode.local,
      );
      final ledgerRepo = LedgerRepository(
        api,
        localCore: localCore,
        dataMode: LiflyDataMode.local,
      );
      final taskRepo = TaskRepository(
        api,
        localCore: localCore,
        dataMode: LiflyDataMode.local,
      );
      final homeRepo = HomeOverviewRepository(
        api,
        localCore: localCore,
        dataMode: LiflyDataMode.local,
      );

      await memoRepo.create({
        'type': 'memo',
        'title': '本地备忘',
        'content_markdown': '首页混合流内容',
      });
      await ledgerRepo.create({
        'direction': 'expense',
        'amount': 18.0,
        'merchant': '食堂',
        'category_id': 'food',
      });
      await taskRepo.create({
        'title': '今天要做',
        'due_at': DateTime.now().toUtc().toIso8601String(),
        'priority': 'high',
      });

      final overview = await homeRepo.load();

      expect(overview.sourceMode, 'local');
      expect(overview.todayMetrics.memoTotal, 1);
      expect(overview.todayMetrics.taskTodo, 1);
      expect(overview.todayMetrics.taskDueToday, 1);
      expect(overview.financeOverview.monthExpense, 18.0);
      expect(overview.financeOverview.budgetState, 'not_configured');
      expect(
        overview.recentActivity.map((item) => item.entityType),
        contains('memo'),
      );
      expect(
        overview.recentActivity.map((item) => item.entityType),
        contains('task'),
      );
      expect(
        overview.recentActivity.map((item) => item.entityType),
        contains('ledger_transaction'),
      );
    },
  );

  test(
    'LedgerRepository computes local overview and category summary',
    () async {
      final ledgerRepo = LedgerRepository(
        api,
        localCore: localCore,
        dataMode: LiflyDataMode.local,
      );

      await ledgerRepo.create({
        'direction': 'expense',
        'amount': 40.0,
        'merchant': '餐厅',
        'category_id': 'food',
      });
      await ledgerRepo.create({
        'direction': 'expense',
        'amount': 10.0,
        'merchant': '公交',
        'category_id': 'transport',
      });

      final overview = await ledgerRepo.overview();
      final categories = await ledgerRepo.categorySummary();
      final insights = await ledgerRepo.insights();

      expect(overview['source_mode'], 'local');
      expect(overview['month_expense'], 50.0);
      expect(overview['budget_state'], 'not_configured');
      expect(categories.first['category_id'], 'food');
      expect(categories.first['amount'], 40.0);
      expect(categories.first['ratio'], 0.8);
      expect(insights.first['id'], 'budget_not_configured');
    },
  );

  test(
    'LedgerRepository falls back to Local Core when cloud overview fails',
    () async {
      final failingDio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
      failingDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'offline',
              ),
            );
          },
        ),
      );
      final repo = LedgerRepository(
        ApiClient(baseUrl: 'http://localhost/api/v1', dio: failingDio),
        localCore: localCore,
        dataMode: LiflyDataMode.api,
      );
      final localLedgerRepo = LedgerRepository(
        api,
        localCore: localCore,
        dataMode: LiflyDataMode.local,
      );

      await localLedgerRepo.create({
        'direction': 'expense',
        'amount': 12.0,
        'merchant': '本地账单',
      });

      final overview = await repo.overview();

      expect(overview['source_mode'], 'fallback');
      expect(overview['month_expense'], 12.0);
    },
  );

  test(
    'HomeOverviewRepository loads cloud home overview endpoint first',
    () async {
      String? requestedPath;
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedPath = options.path;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'schema_version': 'home_overview.v1',
                    'generated_at': '2026-07-07T12:00:00Z',
                    'user_timezone': 'UTC',
                    'source_mode': 'api',
                    'today_metrics': {
                      'memo_total': 1,
                      'task_todo': 0,
                      'task_total': 0,
                      'task_overdue': 0,
                      'task_due_today': 0,
                    },
                    'finance_overview': {
                      'month_income': 0,
                      'month_expense': 0,
                      'transaction_count': 0,
                      'budget_state': 'not_configured',
                      'budget_amount': null,
                      'budget_used': null,
                      'budget_progress': null,
                      'budget_remaining': null,
                      'currency': 'CNY',
                      'category_breakdown': const [],
                      'insights': const [],
                    },
                    'daily_trend': const [],
                    'recent_activity': const [],
                    'sync_summary': {'status': 'api_available'},
                    'import_summary': {'status': 'idle'},
                    'settings_summary': {'status': 'ok'},
                  },
                },
              ),
            );
          },
        ),
      );
      final homeRepo = HomeOverviewRepository(
        ApiClient(baseUrl: 'http://localhost/api/v1', dio: dio),
        localCore: localCore,
        dataMode: LiflyDataMode.api,
      );

      final overview = await homeRepo.load();

      expect(requestedPath, '/home/overview');
      expect(overview.sourceMode, 'api');
      expect(overview.todayMetrics.memoTotal, 1);
    },
  );

  test('HomeOverview parses cloud home overview schema', () {
    final overview = HomeOverview.fromDashboardJson({
      'schema_version': 'home_overview.v1',
      'generated_at': '2026-07-07T12:00:00Z',
      'user_timezone': 'UTC',
      'source_mode': 'api',
      'today_metrics': {
        'memo_total': 2,
        'task_todo': 1,
        'task_total': 3,
        'task_overdue': 1,
        'task_due_today': 1,
      },
      'finance_overview': {
        'month_income': 200,
        'month_expense': 18.5,
        'transaction_count': 1,
        'budget_state': 'configured',
        'budget_amount': 100,
        'budget_used': 18.5,
        'budget_progress': 0.185,
        'budget_remaining': 81.5,
        'currency': 'CNY',
        'category_breakdown': [
          {
            'category_id': 'food',
            'category_name': '餐饮',
            'direction': 'expense',
            'amount': 18.5,
            'ratio': 1.0,
            'transaction_count': 1,
            'color_token': 'orange',
            'icon_token': 'restaurant',
          },
        ],
        'insights': [
          {
            'id': 'budget_ok',
            'type': 'budget',
            'level': 'info',
            'title': '预算正常',
            'description': '本月预算仍充足',
          },
        ],
      },
      'daily_trend': [
        {'day': '2026-07-07', 'total': 18.5},
      ],
      'recent_activity': [
        {
          'id': 'ledger_transaction_tx_1',
          'entity_type': 'ledger_transaction',
          'entity_id': 'tx_1',
          'title': '食堂',
          'occurred_at': '2026-07-07T12:00:00Z',
          'amount': 18.5,
          'direction': 'expense',
        },
      ],
      'sync_summary': {
        'status': 'ready',
        'mode': 'server',
        'powersync_configured': true,
        'pending_asset_count': 2,
        'failed_asset_count': 0,
        'synced_asset_count': 4,
      },
      'import_summary': {
        'status': 'committed',
        'latest_batch_id': 'batch-1',
        'source_provider': 'alipay',
        'filename': 'alipay.csv',
        'total_rows': 20,
        'valid_rows': 18,
        'duplicate_rows': 2,
        'created_at': '2026-07-07T10:00:00Z',
        'committed_at': '2026-07-07T10:05:00Z',
      },
      'settings_summary': {
        'status': 'ok',
        'mode': 'server',
        'data_mode': 'api',
        'local_core_available': false,
        'timezone': 'UTC',
        'database_configured': true,
        'powersync_configured': true,
        'object_storage_configured': true,
      },
    });

    expect(overview.schemaVersion, 'home_overview.v1');
    expect(overview.sourceMode, 'api');
    expect(overview.todayMetrics.memoTotal, 2);
    expect(overview.todayMetrics.taskOverdue, 1);
    expect(overview.financeOverview.monthExpense, 18.5);
    expect(overview.financeOverview.budgetAmount, 100);
    expect(overview.financeOverview.budgetProgress, 0.185);
    expect(
      overview.financeOverview.categoryBreakdown.single.categoryName,
      '餐饮',
    );
    expect(overview.financeOverview.insights.single.id, 'budget_ok');
    expect(overview.dailyTrend.single.total, 18.5);
    expect(overview.recentActivity.single.entityType, 'ledger_transaction');
    expect(overview.syncStatus, 'ready');
    expect(overview.syncSummary.pendingAssetCount, 2);
    expect(overview.syncSummary.powerSyncConfigured, isTrue);
    expect(overview.importStatus, 'committed');
    expect(overview.importSummary.latestBatchId, 'batch-1');
    expect(overview.importSummary.validRows, 18);
    expect(overview.settingsSummary.databaseConfigured, isTrue);
  });

  test(
    'HomeOverviewRepository falls back to Local Core when cloud load fails',
    () async {
      final failingDio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
      failingDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'offline',
              ),
            );
          },
        ),
      );
      final failingApi = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        dio: failingDio,
      );
      final memoRepo = MemoRepository(
        api,
        localCore: localCore,
        dataMode: LiflyDataMode.local,
      );
      final homeRepo = HomeOverviewRepository(
        failingApi,
        localCore: localCore,
        dataMode: LiflyDataMode.api,
      );

      await memoRepo.create({
        'type': 'memo',
        'title': '离线可见备忘',
        'content_markdown': 'cloud failed local fallback',
      });

      final overview = await homeRepo.load();

      expect(overview.sourceMode, 'fallback');
      expect(overview.todayMetrics.memoTotal, 1);
      expect(
        overview.recentActivity.map((item) => item.entityType),
        contains('memo'),
      );
    },
  );
}
