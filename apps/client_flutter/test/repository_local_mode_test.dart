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
    });
    final page = await repo.listPage(q: 'stored locally');

    expect(memo.id, 'local_memo_0001');
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
  });

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
    final summary = await repo.summary();

    expect(tx.id, 'local_tx_0001');
    expect(summary['expense_total'], 12.5);
    expect(summary['transaction_count'], 1);
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
        'budget_state': 'not_configured',
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
      'sync_summary': {'status': 'api_available'},
      'import_summary': {'status': 'idle'},
      'settings_summary': {'status': 'ok'},
    });

    expect(overview.schemaVersion, 'home_overview.v1');
    expect(overview.sourceMode, 'api');
    expect(overview.todayMetrics.memoTotal, 2);
    expect(overview.todayMetrics.taskOverdue, 1);
    expect(overview.financeOverview.monthExpense, 18.5);
    expect(overview.dailyTrend.single.total, 18.5);
    expect(overview.recentActivity.single.entityType, 'ledger_transaction');
    expect(overview.syncStatus, 'api_available');
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
