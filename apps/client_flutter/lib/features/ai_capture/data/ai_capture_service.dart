import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';

class AiCaptureService {
  const AiCaptureService({
    required this.api,
    required this.dataMode,
  });

  final ApiClient api;
  final LiflyDataMode dataMode;

  String get modeLabel {
    return switch (dataMode) {
      LiflyDataMode.api => 'Cloud MCP',
      LiflyDataMode.local => 'Local MCP（桌面端待接入）',
    };
  }

  bool get supportsCloudCapture => dataMode == LiflyDataMode.api;

  Future<AiCaptureParseResult> parse({
    required String text,
    String timezone = 'Asia/Shanghai',
    String locale = 'zh-CN',
  }) async {
    _ensureCloudMode();
    final data = await api.post(
      '/mcp/capture/parse',
      data: {
        'text': text,
        'timezone': timezone,
        'locale': locale,
      },
    );
    return AiCaptureParseResult.fromJson(data);
  }

  Future<AiCaptureCommitResult> commit({
    required String captureId,
    required List<int> selectedActionIndexes,
  }) async {
    _ensureCloudMode();
    final data = await api.post(
      '/mcp/capture/commit',
      data: {
        'capture_id': captureId,
        'selected_action_indexes': selectedActionIndexes,
      },
    );
    return AiCaptureCommitResult.fromJson(data);
  }

  Future<AiCaptureUndoResult> undo({required String undoToken}) async {
    _ensureCloudMode();
    final data = await api.post(
      '/mcp/capture/undo',
      data: {'undo_token': undoToken},
    );
    return AiCaptureUndoResult.fromJson(data);
  }

  void _ensureCloudMode() {
    if (dataMode == LiflyDataMode.api) return;
    throw StateError('Local MCP 需要桌面端 host 接入；手机端/Web 当前请使用 Cloud MCP。');
  }
}
