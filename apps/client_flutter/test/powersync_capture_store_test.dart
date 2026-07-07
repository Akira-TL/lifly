import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/powersync_persistence_harness.dart';

void main() {
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

      final parsed = await bridge.captureParse({
        'text': '记录一下今天继续补 AI Capture 地基',
        'timezone': 'Asia/Shanghai',
        'locale': 'zh-CN',
      }, context);

      expect(parsed.captureId, startsWith('local_capture_'));
      expect(parsed.originalText, contains('AI Capture 地基'));
      expect(parsed.actions, hasLength(1));
      expect(parsed.turns, hasLength(1));
      expect(parsed.turns.first.turnStatus, 'parsed');

      final sessionRow = await service.db.get(
        'SELECT original_text, session_status FROM mcp_capture_sessions WHERE capture_id = ?',
        [parsed.captureId],
      );
      expect(sessionRow['session_status'], 'parsed');
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

      service.dispose();
    },
  );
}
