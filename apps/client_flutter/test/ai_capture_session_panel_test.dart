import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_capture_session_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AI session panel keeps history rows compact and metadata readable',
    (tester) async {
      final sessions = [
        _session('capture-1', '整理今天的任务和晚上的安排', 4, DateTime(2026, 8, 11, 1, 10)),
        _session('capture-2', '记录午饭和咖啡', 2, DateTime(2026, 8, 10, 18, 30)),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              height: 600,
              child: AiCaptureSessionPanel(
                sessions: sessions,
                selectedCaptureId: 'capture-1',
                onSelected: (_) {},
                onNew: () {},
              ),
            ),
          ),
        ),
      );

      final first = find.text('整理今天的任务和晚上的安排');
      final second = find.text('记录午饭和咖啡');
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(find.textContaining('4 条'), findsOneWidget);
      expect(find.textContaining('08/11 01:10'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
      expect(
        tester.getTopLeft(second).dy - tester.getTopLeft(first).dy,
        lessThan(62),
      );
    },
  );
}

AiCaptureSession _session(
  String captureId,
  String title,
  int turnCount,
  DateTime updatedAt,
) {
  return AiCaptureSession.fromJson({
    'capture_id': captureId,
    'original_text': title,
    'timezone': 'Asia/Shanghai',
    'locale': 'zh-CN',
    'actions': const [],
    'requires_confirmation': false,
    'committed': true,
    'session_status': 'active',
    'source_channel': 'flutter',
    'created_at': updatedAt
        .subtract(const Duration(hours: 1))
        .toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'turn_count': turnCount,
    'turns': const [],
  });
}
