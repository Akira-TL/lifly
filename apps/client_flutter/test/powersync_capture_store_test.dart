import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/powersync_persistence_harness.dart';

void main() {
  test(
    'PowerSync capture parses local mixed task and ledger input',
    () async {
      final harness = await PowerSyncPersistenceHarness.create(
        'lifly_capture_parse_',
      );
      addTearDown(harness.dispose);

      final service = await harness.openService();
      if (service == null) return;

      final bridge = PowerSyncLocalCoreBridge(syncService: service);
      final parsed = await bridge.captureParse({
        'text': '明天下午提醒我交房租，支付宝昨天有一笔 320 的超市消费',
      }, LocalCoreContext.flutterUser(now: DateTime.utc(2026, 7, 7, 10)));

      expect(parsed.actions.map((item) => item.type), contains('task_create'));
      expect(parsed.actions.map((item) => item.type), contains('expense_create'));
      final expense = parsed.actions.firstWhere(
        (item) => item.type == 'expense_create',
      );
      expect(expense.payload['amount'], 320.0);
      expect(expense.payload['category_id'], 'shopping');
      final task = parsed.actions.firstWhere((item) => item.type == 'task_create');
      expect(task.payload['title'], '交房租');

      service.dispose();
    },
  );

  test(
    'PowerSync capture sessions persist turns, commit refs, and undo refs',
    () async {
      final harness = await PowerSyncPersistenceHarness.create(
        'lifly_capture_store_',
      );
      addTearDown(harness.dispose);

      final service = await harness.openService();
      if (service == null) return;

      final context = LocalCoreContext.flutterUser(
        now: DateTime.utc(2026, 7, 7, 10),
      );
      final bridge = PowerSyncLocalCoreBridge(syncService: service);
      await service.db.execute(
        'INSERT INTO assets('
        'id, user_id, kind, asset_type, external_url, external_provider, '
        'visibility, sync_status, status, created_at, updated_at'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'asset-2',
          'local-dev',
          'external',
          'link',
          'https://example.com/capture-context',
          'web',
          'private',
          'synced',
          'active',
          '2026-07-07T10:00:00Z',
          '2026-07-07T10:00:00Z',
        ],
      );

      final parsed = await bridge.captureParse({
        'text': '记录一下今天继续补 AI Capture 地基',
        'timezone': 'Asia/Shanghai',
        'locale': 'zh-CN',
      }, context);

      expect(parsed.captureId, startsWith('local_capture_'));
      expect(parsed.originalText, contains('AI Capture 地基'));
      expect(parsed.actions, hasLength(1));
      expect(parsed.turns, hasLength(2));
      expect(parsed.turns.first.role, 'user');
      expect(parsed.turns.first.turnStatus, 'accepted');
      expect(parsed.turns.last.role, 'assistant');
      expect(parsed.turns.last.turnStatus, 'parsed');

      final sessionRow = await service.db.get(
        'SELECT original_text, session_status FROM mcp_capture_sessions WHERE capture_id = ?',
        [parsed.captureId],
      );
      expect(sessionRow['session_status'], 'active');
      expect(sessionRow['original_text'], contains('AI Capture 地基'));

      final committed = await bridge.captureCommit({
        'capture_id': parsed.captureId,
        'selected_action_indexes': [0],
      }, context);
      expect(committed.committed, isTrue);
      expect(committed.createdEntities, hasLength(1));
      expect(committed.createdEntities.first.type, 'memo');
      expect(committed.undoToken, startsWith('local_undo_'));

      final memoRow = await service.db.get(
        'SELECT source_capture_id, status FROM memos WHERE id = ?',
        [committed.createdEntities.first.id],
      );
      expect(memoRow['source_capture_id'], parsed.captureId);
      expect(memoRow['status'], 'active');

      final afterCommitTurns = await service.db.get(
        'SELECT count(*) AS count FROM mcp_capture_turns WHERE capture_id = ?',
        [parsed.captureId],
      );
      expect(afterCommitTurns['count'], 2);

      final activeAfterCommit = await bridge.getCaptureSession({
        'capture_id': parsed.captureId,
      }, context);
      expect(activeAfterCommit, isNotNull);
      expect(activeAfterCommit!.sessionStatus, 'active');
      expect(activeAfterCommit.committed, isTrue);
      expect(activeAfterCommit.turns.last.turnStatus, 'committed');
      expect(activeAfterCommit.turns.last.undoToken, committed.undoToken);

      final undone = await bridge.captureUndo({
        'undo_token': committed.undoToken,
      }, context);
      expect(undone.undone, 1);
      expect(
        undone.entities.map((item) => item.id),
        contains(committed.createdEntities.first.id),
      );
      expect(undone.failedEntities, isEmpty);

      final afterUndoMemoRow = await service.db.get(
        'SELECT status FROM memos WHERE id = ?',
        [committed.createdEntities.first.id],
      );
      expect(afterUndoMemoRow['status'], 'ai_trashed');

      final afterUndoTurns = await service.db.get(
        'SELECT count(*) AS count FROM mcp_capture_turns WHERE capture_id = ?',
        [parsed.captureId],
      );
      expect(afterUndoTurns['count'], 3);

      final restored = await bridge.getCaptureSession({
        'capture_id': parsed.captureId,
      }, context);
      expect(restored, isNotNull);
      expect(restored!.turns[1].turnStatus, 'undone');
      expect(restored.turns.last.turnStatus, 'undone');

      final revised = await bridge.reviseCaptureAction({
        'capture_id': parsed.captureId,
        'turn_id': restored.turns[1].id,
        'action_index': 0,
        'payload': {
          'type': 'memo',
          'title': '撤销后修改',
          'content_markdown': '修改后的 Capture 内容',
          'tags': ['capture', 'edited'],
        },
      }, context);
      expect(revised.turnStatus, 'revised');
      expect(revised.supersedesTurnId, restored.turns[1].id);

      final recommitted = await bridge.captureCommit({
        'capture_id': parsed.captureId,
        'turn_id': revised.id,
        'selected_action_indexes': [0],
      }, context);
      expect(recommitted.committed, isTrue);

      final continued = await bridge.appendCaptureTurn({
        'capture_id': parsed.captureId,
        'text': '继续第二轮，记录持续会话',
        'asset_ids': ['asset-2'],
      }, context);
      expect(continued.sessionStatus, 'active');
      expect(continued.turns.last.role, 'assistant');
      expect(continued.turns.last.assetIds, ['asset-2']);
      expect(continued.turns.last.assetContext, hasLength(1));
      expect(continued.turns.last.assetContext.single.status, 'metadata_only');
      expect(
        continued.turns.last.assetContext.single.requiredCapability,
        'external_content_fetch',
      );
      expect(continued.turns.last.turnStatus, 'parsed');

      final dismissed = await bridge.dismissCaptureSession({
        'capture_id': parsed.captureId,
        'reason': '用户关闭会话',
      }, context);
      expect(dismissed.sessionStatus, 'dismissed');
      expect(dismissed.turns.last.turnStatus, 'dismissed');

      service.dispose();
    },
  );
}
