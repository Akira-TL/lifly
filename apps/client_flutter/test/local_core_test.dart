import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 6, 25, 12);
  final context = LocalCoreContext.localMcp('test_tool', now: fixedNow);

  test('FakeLocalCoreBridge reports health', () async {
    final core = FakeLocalCoreBridge();
    final health = await core.health();

    expect(health.status, 'ok');
    expect(health.mode, 'fake');
  });

  test('FakeLocalCoreBridge creates and searches memos', () async {
    final core = FakeLocalCoreBridge();
    final memo = await core.createMemo({
      'type': 'memo',
      'title': 'Local memo',
      'content_markdown': 'created through dart local core',
      'tags': ['local'],
    }, context);

    expect(memo.id, 'local_memo_0001');
    expect(memo.revision, 1);

    final results = await core.searchMemos({'q': 'dart local core', 'limit': 20}, context);
    expect(results.map((item) => item.id), contains(memo.id));
  });

  test('FakeLocalCoreBridge creates expenses and summarizes them', () async {
    final core = FakeLocalCoreBridge();
    final tx = await core.createExpense({
      'direction': 'expense',
      'amount': 12.5,
      'currency': 'CNY',
      'merchant': 'Local Merchant',
      'note': 'local expense',
    }, context);

    expect(tx.id, 'local_tx_0001');

    final results = await core.searchExpenses({'q': 'merchant', 'limit': 20}, context);
    expect(results, hasLength(1));

    final summary = await core.summarizeExpenses({'period': 'current_month'}, context);
    expect(summary.totalExpense, 12.5);
    expect(summary.count, 1);
  });

  test('FakeLocalCoreBridge creates, lists, and completes tasks', () async {
    final core = FakeLocalCoreBridge();
    final task = await core.createTask({
      'title': 'Local task',
      'description': 'local task description',
      'priority': 'normal',
    }, context);

    expect(task.id, 'local_task_0001');
    expect(task.taskStatus, 'todo');

    final tasks = await core.listTasks({'task_status': 'todo', 'limit': 20}, context);
    expect(tasks.map((item) => item.id), contains(task.id));

    final completed = await core.completeTask({'task_id': task.id}, context);
    expect(completed.taskStatus, 'done');
    expect(completed.completedAt, fixedNow);
    expect(completed.revision, 2);
  });

  test('FakeLocalCoreBridge parses, commits, and undoes capture sessions', () async {
    final core = FakeLocalCoreBridge();
    final parsed = await core.captureParse({
      'text': '记一下 Dart Local Core capture',
      'timezone': 'Asia/Shanghai',
      'locale': 'zh-CN',
    }, context);

    expect(parsed.captureId, 'local_capture_0001');
    expect(parsed.actions, hasLength(1));

    final committed = await core.captureCommit({'capture_id': parsed.captureId}, context);
    expect(committed.committed, isTrue);
    expect(committed.createdEntities, hasLength(1));
    expect(committed.undoToken, 'local_undo_0001');

    final undone = await core.captureUndo({'undo_token': committed.undoToken}, context);
    expect(undone.undone, 1);
    expect(undone.failedEntities, isEmpty);
  });
}
