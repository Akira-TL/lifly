import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI capture exposes product-facing mode labels', () {
    final api = ApiClient(baseUrl: 'http://localhost/api/v1');
    expect(
      AiCaptureService(
        api: api,
        dataMode: LiflyDataMode.local,
        localCore: FakeLocalCoreBridge(),
      ).modeLabel,
      '本地处理',
    );
    expect(
      AiCaptureService(api: api, dataMode: LiflyDataMode.local).modeLabel,
      '本地处理不可用',
    );
    expect(
      AiCaptureService(api: api, dataMode: LiflyDataMode.api).modeLabel,
      '云端处理',
    );
  });

  test(
    'AI capture keeps continuous turns and supports undo then revise',
    () async {
      final service = AiCaptureService(
        api: ApiClient(baseUrl: 'http://localhost/api/v1'),
        dataMode: LiflyDataMode.local,
        localCore: FakeLocalCoreBridge(),
      );

      final parsed = await service.parse(
        text: '记录一下第一轮内容',
        assetIds: const ['asset-1'],
      );
      expect(parsed.captureId, isNotEmpty);
      expect(parsed.turnId, isNotNull);

      final afterAppend = await service.appendTurn(
        captureId: parsed.captureId,
        text: '记录一下第二轮内容',
      );
      expect(afterAppend.sessionStatus, 'active');
      expect(afterAppend.turns, hasLength(4));
      expect(afterAppend.turns.where((turn) => turn.role == 'user'), hasLength(2));
      expect(
        afterAppend.turns.where((turn) => turn.role == 'assistant'),
        hasLength(2),
      );

      final sourceTurn = afterAppend.turns.last;
      final revised = await service.reviseAction(
        captureId: parsed.captureId,
        turnId: sourceTurn.id,
        actionIndex: 0,
        payload: const {
          'type': 'memo',
          'title': '修改后的标题',
          'content_markdown': '修改后的第二轮内容',
          'tags': ['capture', 'edited'],
        },
        note: '用户修改了 AI 设置内容',
      );
      expect(revised.turnStatus, 'revised');
      expect(revised.supersedesTurnId, sourceTurn.id);
      expect(revised.actions.single.payload['title'], '修改后的标题');

      final committed = await service.commit(
        captureId: parsed.captureId,
        turnId: revised.id,
        selectedActionIndexes: const [0],
      );
      expect(committed.committed, isTrue);
      expect(committed.undoToken, isNotEmpty);
      expect(committed.createdEntities, hasLength(1));

      final afterCommit = await service.getSession(parsed.captureId);
      final committedTurn = afterCommit.turns.firstWhere(
        (turn) => turn.id == revised.id,
      );
      expect(committedTurn.turnStatus, 'committed');
      expect(committedTurn.canUndo, isTrue);
      expect(committedTurn.resultEntities, hasLength(1));

      final undone = await service.undo(undoToken: committed.undoToken);
      expect(undone.undone, 1);
      expect(undone.entities, hasLength(1));

      final afterUndo = await service.getSession(parsed.captureId);
      final undoneTurn = afterUndo.turns.firstWhere(
        (turn) => turn.id == revised.id,
      );
      expect(undoneTurn.turnStatus, 'undone');
      expect(afterUndo.turns.last.role, 'system');
      expect(afterUndo.turns.last.turnStatus, 'undone');

      final revisedAgain = await service.reviseAction(
        captureId: parsed.captureId,
        turnId: revised.id,
        actionIndex: 0,
        payload: const {
          'type': 'memo',
          'title': '撤销后再次修改',
          'content_markdown': '新的内容',
          'tags': ['capture'],
        },
      );
      expect(revisedAgain.turnStatus, 'revised');
      expect(revisedAgain.actions.single.payload['title'], '撤销后再次修改');

      final dismissed = await service.dismissSession(
        parsed.captureId,
        reason: '用户关闭会话',
      );
      expect(dismissed.isDismissed, isTrue);
      expect(dismissed.turns.last.turnStatus, 'dismissed');

      final active = await service.listSessions();
      expect(active.items.map((item) => item.captureId), isNot(contains(parsed.captureId)));
      final all = await service.listSessions(status: 'all');
      expect(all.items.map((item) => item.captureId), contains(parsed.captureId));
    },
  );
}
