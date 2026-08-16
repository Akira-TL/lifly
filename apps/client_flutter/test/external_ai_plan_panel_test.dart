import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_execution_runtime.dart';
import 'package:client_flutter/features/ai_capture/data/external_ai_action_committer.dart';
import 'package:client_flutter/features/ai_capture/widgets/external_ai_plan_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _action = MemoCreateCandidateAction(
  memoType: 'memo',
  contentMarkdown: '自动写入的备忘内容',
  confidence: 0.9,
  rawText: 'raw',
);

const _plan = ExternalAiPlanResult(
  sourceLabel: '我的电脑 · Desktop',
  actions: [_action],
);

Widget _app({
  required Map<int, ExternalAiActionCommitResult> commits,
  Set<int> busy = const {},
  Set<int> undone = const {},
}) => MaterialApp(
  home: Scaffold(
    body: ExternalAiPlanPanel(
      plan: _plan,
      commits: commits,
      busyIndexes: busy,
      undoneIndexes: undone,
      onCommit: (_) {},
      onUndo: (_) {},
      onClose: () {},
    ),
  ),
);

void main() {
  testWidgets('successful AI action is presented as completed with undo', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        commits: const {
          0: ExternalAiActionCommitResult(
            captureId: 'capture-1',
            entityType: 'memo',
            entityId: 'memo-1',
            undoToken: 'undo-1',
          ),
        },
      ),
    );

    expect(find.text('AI 已默认执行可用操作；如需取消，可在下方点击“撤回”。'), findsOneWidget);
    expect(find.text('自动写入的备忘内容'), findsOneWidget);
    expect(find.text('撤回'), findsOneWidget);
    expect(find.text('提交'), findsNothing);
  });

  testWidgets('undone AI action stays visible as withdrawn', (tester) async {
    await tester.pumpWidget(
      _app(
        commits: const {
          0: ExternalAiActionCommitResult(
            captureId: 'capture-1',
            entityType: 'memo',
            entityId: 'memo-1',
            undoToken: 'undo-1',
          ),
        },
        undone: const {0},
      ),
    );

    expect(find.text('已撤回'), findsOneWidget);
    expect(find.text('撤回'), findsNothing);
  });
}
