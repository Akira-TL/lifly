import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_capture_turn_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI result card shows created entity, attachment boundary, and undo', (
    tester,
  ) async {
    var undone = false;
    final turn = AiCaptureTurn(
      id: 'turn-1',
      captureId: 'capture-1',
      turnIndex: 2,
      role: 'assistant',
      text: null,
      assetIds: const ['asset-pdf'],
      assetContext: const [
        AiCaptureAssetContext(
          assetId: 'asset-pdf',
          assetType: 'pdf',
          name: '计划.pdf',
          mimeType: 'application/pdf',
          status: 'unsupported',
          extractor: 'pdf_adapter',
          requiredCapability: 'pdf_text_extraction',
        ),
      ],
      actions: const [
        AiCaptureAction(
          type: 'task_create',
          payload: {'title': '完成计划复核'},
          confidence: 0.9,
        ),
      ],
      selectedActionIndexes: const [0],
      resultEntities: const [AiCaptureEntityRef(type: 'task', id: 'task-1')],
      undoToken: 'undo-1',
      supersedesTurnId: null,
      turnStatus: 'committed',
      createdAt: DateTime.utc(2026, 7, 11),
      updatedAt: DateTime.utc(2026, 7, 11),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiCaptureTurnCard(
            turn: turn,
            busy: false,
            onCommit: (_, _) async {},
            onRevise: (_, _, _) async {},
            onUndo: (_) async => undone = true,
          ),
        ),
      ),
    );

    expect(find.text('AI 已完成设置'), findsOneWidget);
    expect(find.text('任务 · task-1'), findsOneWidget);
    expect(find.text('计划.pdf'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(undone, isTrue);
  });
}
