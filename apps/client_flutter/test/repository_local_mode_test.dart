import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/repositories/home_overview_repository.dart';
import 'package:client_flutter/data/repositories/ledger_repository.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
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
