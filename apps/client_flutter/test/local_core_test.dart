import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 6, 25, 12);
  final context = LocalCoreContext.localMcp('test_tool', now: fixedNow);

  test('Local Core defaults to the PowerSync development user', () {
    expect(context.userId, 'local-dev');
    expect(LocalCoreContext.flutterUser().userId, 'local-dev');
  });

  test('FakeLocalCoreBridge reports health', () async {
    final core = FakeLocalCoreBridge();
    final health = await core.health();

    expect(health.status, 'ok');
    expect(health.mode, 'fake');
  });

  test(
    'FakeLocalCoreBridge creates, updates, searches, and deletes memos',
    () async {
      final core = FakeLocalCoreBridge();
      final memo = await core.createMemo({
        'type': 'memo',
        'title': 'Local memo',
        'content_markdown': 'created through dart local core',
        'tags': ['local'],
      }, context);

      expect(memo.id, 'local_memo_0001');
      expect(memo.revision, 1);

      final results = await core.searchMemos({
        'q': 'dart local core',
        'limit': 20,
      }, context);
      expect(results.map((item) => item.id), contains(memo.id));

      final updated = await core.updateMemo({
        'memo_id': memo.id,
        'title': 'Updated local memo',
        'content_markdown': 'updated through fake local core',
        'tags': ['local', 'updated'],
      }, context);
      expect(updated.revision, 2);
      expect(updated.title, 'Updated local memo');
      expect(updated.tags, ['local', 'updated']);

      final deleted = await core.deleteMemo({'memo_id': memo.id}, context);
      expect(deleted.revision, 3);
      expect(deleted.status, 'deleted');

      final afterDelete = await core.searchMemos({
        'q': 'updated',
        'limit': 20,
      }, context);
      expect(afterDelete.map((item) => item.id), isNot(contains(memo.id)));
    },
  );

  test(
    'FakeLocalCoreBridge creates, searches, summarizes, and deletes expenses',
    () async {
      final core = FakeLocalCoreBridge();
      final tx = await core.createExpense({
        'direction': 'expense',
        'amount': 12.5,
        'currency': 'CNY',
        'merchant': 'Local Merchant',
        'note': 'local expense',
      }, context);

      expect(tx.id, 'local_tx_0001');

      final results = await core.searchExpenses({
        'q': 'merchant',
        'limit': 20,
      }, context);
      expect(results, hasLength(1));

      final summary = await core.summarizeExpenses({
        'period': 'current_month',
      }, context);
      expect(summary.totalExpense, 12.5);
      expect(summary.count, 1);

      final deleted = await core.deleteExpense({
        'transaction_id': tx.id,
      }, context);
      expect(deleted.status, 'deleted');
      expect(deleted.revision, 2);

      final afterDelete = await core.searchExpenses({
        'q': 'merchant',
        'limit': 20,
      }, context);
      expect(afterDelete, isEmpty);
    },
  );

  test(
    'FakeLocalCoreBridge creates, updates, completes, and deletes tasks',
    () async {
      final core = FakeLocalCoreBridge();
      final task = await core.createTask({
        'title': 'Local task',
        'description': 'local task description',
        'priority': 'normal',
      }, context);

      expect(task.id, 'local_task_0001');
      expect(task.taskStatus, 'todo');

      final tasks = await core.listTasks({
        'task_status': 'todo',
        'limit': 20,
      }, context);
      expect(tasks.map((item) => item.id), contains(task.id));

      final updated = await core.updateTask({
        'task_id': task.id,
        'title': 'Updated local task',
        'priority': 'high',
      }, context);
      expect(updated.title, 'Updated local task');
      expect(updated.priority, 'high');
      expect(updated.revision, 2);

      final completed = await core.completeTask({'task_id': task.id}, context);
      expect(completed.taskStatus, 'done');
      expect(completed.completedAt, fixedNow);
      expect(completed.revision, 3);

      final deleted = await core.deleteTask({'task_id': task.id}, context);
      expect(deleted.status, 'deleted');
      expect(deleted.revision, 4);

      final afterDelete = await core.listTasks({'limit': 20}, context);
      expect(afterDelete.map((item) => item.id), isNot(contains(task.id)));
    },
  );

  test(
    'FakeLocalCoreBridge parses, commits, and undoes capture sessions',
    () async {
      final core = FakeLocalCoreBridge();
      final parsed = await core.captureParse({
        'text': '记一下 Dart Local Core capture',
        'timezone': 'Asia/Shanghai',
        'locale': 'zh-CN',
      }, context);

      expect(parsed.captureId, 'local_capture_0001');
      expect(parsed.actions, hasLength(1));

      final committed = await core.captureCommit({
        'capture_id': parsed.captureId,
      }, context);
      expect(committed.committed, isTrue);
      expect(committed.createdEntities, hasLength(1));
      expect(committed.undoToken, 'local_undo_0001');

      final undone = await core.captureUndo({
        'undo_token': committed.undoToken,
      }, context);
      expect(undone.undone, 1);
      expect(undone.failedEntities, isEmpty);
    },
  );
}
