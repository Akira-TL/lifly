import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/repositories/ledger_repository.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
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
}
