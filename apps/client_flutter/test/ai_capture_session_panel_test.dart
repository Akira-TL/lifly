import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_service.dart';
import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:client_flutter/features/ai_capture/pages/ai_capture_page.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_capture_session_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('AI capture hides implementation errors from users', (
    tester,
  ) async {
    final service = AiCaptureService(
      api: _FailingAiApiClient(),
      dataMode: LiflyDataMode.api,
    );
    await tester.pumpWidget(
      Provider<AiCaptureService>.value(
        value: service,
        child: const MaterialApp(home: AiCapturePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 操作失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('MCP transport leaked'), findsNothing);
  });

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

class _FailingAiApiClient extends ApiClient {
  _FailingAiApiClient() : super(baseUrl: 'http://localhost/api/v1');

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    throw StateError('MCP transport leaked');
  }
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
