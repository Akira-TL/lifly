import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';

class AiCaptureService {
  const AiCaptureService({
    required this.api,
    required this.dataMode,
    this.localCore,
  });

  final ApiClient api;
  final LiflyDataMode dataMode;
  final LocalCoreBridge? localCore;

  String get modeLabel {
    return switch (dataMode) {
      LiflyDataMode.api => 'Cloud MCP',
      LiflyDataMode.local =>
        localCore == null ? 'Local Core 未接入' : 'Local Core 本地捕获',
    };
  }

  bool get supportsCloudCapture => dataMode == LiflyDataMode.api;

  bool get supportsCapture =>
      dataMode == LiflyDataMode.api || localCore != null;

  Future<AiCaptureParseResult> parse({
    required String text,
    String timezone = 'Asia/Shanghai',
    String locale = 'zh-CN',
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final session = await _requireLocalCore().captureParse({
        'text': text,
        'timezone': timezone,
        'locale': locale,
      }, LocalCoreContext.flutterUser());
      return _parseResultFromLocal(session);
    }

    final data = await api.post(
      '/mcp/capture/parse',
      data: {'text': text, 'timezone': timezone, 'locale': locale},
    );
    return AiCaptureParseResult.fromJson(data);
  }

  Future<AiCaptureCommitResult> commit({
    required String captureId,
    required List<int> selectedActionIndexes,
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final result = await _requireLocalCore().captureCommit({
        'capture_id': captureId,
        'selected_action_indexes': selectedActionIndexes,
      }, LocalCoreContext.flutterUser());
      return _commitResultFromLocal(result);
    }

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
    if (dataMode == LiflyDataMode.local) {
      final result = await _requireLocalCore().captureUndo({
        'undo_token': undoToken,
      }, LocalCoreContext.flutterUser());
      return _undoResultFromLocal(result);
    }

    final data = await api.post(
      '/mcp/capture/undo',
      data: {'undo_token': undoToken},
    );
    return AiCaptureUndoResult.fromJson(data);
  }

  LocalCoreBridge _requireLocalCore() {
    final bridge = localCore;
    if (bridge == null) {
      throw StateError('Local Core 未接入，无法执行本地 Capture。');
    }
    return bridge;
  }

  AiCaptureParseResult _parseResultFromLocal(LocalCaptureSession session) {
    return AiCaptureParseResult(
      captureId: session.captureId,
      actions: session.actions.map(_actionFromLocal).toList(growable: false),
      requiresConfirmation: session.requiresConfirmation,
    );
  }

  AiCaptureAction _actionFromLocal(LocalCaptureAction action) {
    return AiCaptureAction(
      type: action.type,
      payload: Map<String, dynamic>.from(action.payload),
      confidence: action.confidence,
    );
  }

  AiCaptureCommitResult _commitResultFromLocal(
    LocalCaptureCommitResult result,
  ) {
    return AiCaptureCommitResult(
      committed: result.committed,
      createdEntities: result.createdEntities.map(_entityFromLocal).toList(),
      failedActions: const [],
      undoToken: result.undoToken,
    );
  }

  AiCaptureUndoResult _undoResultFromLocal(LocalCaptureUndoResult result) {
    return AiCaptureUndoResult(
      undone: result.undone,
      entities: result.entities.map(_entityFromLocal).toList(),
      failedEntities: result.failedEntities.map(_entityFromLocal).toList(),
    );
  }

  AiCaptureEntityRef _entityFromLocal(LocalCoreEntityRef ref) {
    return AiCaptureEntityRef(type: ref.type, id: ref.id);
  }
}
