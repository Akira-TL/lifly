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
    List<String> assetIds = const [],
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final session = await _requireLocalCore().captureParse({
        'text': text,
        'timezone': timezone,
        'locale': locale,
        'asset_ids': assetIds,
      }, LocalCoreContext.flutterUser());
      return _parseResultFromLocal(session);
    }

    final data = await api.post(
      '/mcp/capture/parse',
      data: {
        'text': text,
        'timezone': timezone,
        'locale': locale,
        'asset_ids': assetIds,
      },
    );
    return AiCaptureParseResult.fromJson(data);
  }

  Future<AiCaptureSessionPage> listSessions({
    String status = 'active',
    int limit = 20,
    int offset = 0,
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final items = await _requireLocalCore().listCaptureSessions({
        'status': status,
        'limit': limit,
        'offset': offset,
      }, LocalCoreContext.flutterUser());
      return AiCaptureSessionPage(
        items: items.map(_sessionFromLocal).toList(growable: false),
        total: offset + items.length,
        limit: limit,
        offset: offset,
      );
    }
    final data = await api.get(
      '/mcp/capture/sessions',
      params: {'status': status, 'limit': limit, 'offset': offset},
    );
    return AiCaptureSessionPage.fromJson(data);
  }

  Future<AiCaptureSession> getSession(String captureId) async {
    if (dataMode == LiflyDataMode.local) {
      final session = await _requireLocalCore().getCaptureSession({
        'capture_id': captureId,
      }, LocalCoreContext.flutterUser());
      if (session == null) {
        throw StateError('Capture session not found: $captureId');
      }
      return _sessionFromLocal(session);
    }
    final data = await api.get('/mcp/capture/sessions/$captureId');
    return AiCaptureSession.fromJson(data);
  }

  Future<AiCaptureSession> appendTurn({
    required String captureId,
    required String text,
    List<String> assetIds = const [],
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final session = await _requireLocalCore().appendCaptureTurn({
        'capture_id': captureId,
        'text': text,
        'asset_ids': assetIds,
      }, LocalCoreContext.flutterUser());
      return _sessionFromLocal(session);
    }
    final data = await api.post(
      '/mcp/capture/sessions/$captureId/turns',
      data: {'text': text, 'asset_ids': assetIds},
    );
    return AiCaptureSession.fromJson(data);
  }

  Future<AiCaptureTurn> reviseAction({
    required String captureId,
    required String turnId,
    required int actionIndex,
    required Map<String, dynamic> payload,
    String? actionType,
    double? confidence,
    String? note,
  }) async {
    final request = <String, dynamic>{
      'action_index': actionIndex,
      'payload': payload,
      'action_type': ?actionType,
      'confidence': ?confidence,
      'note': ?note,
    };
    if (dataMode == LiflyDataMode.local) {
      final turn = await _requireLocalCore().reviseCaptureAction({
        'capture_id': captureId,
        'turn_id': turnId,
        ...request,
      }, LocalCoreContext.flutterUser());
      return _turnFromLocal(turn);
    }
    final data = await api.post(
      '/mcp/capture/sessions/$captureId/turns/$turnId/revise',
      data: request,
    );
    return AiCaptureTurn.fromJson(
      Map<String, dynamic>.from(data['turn'] as Map? ?? const {}),
    );
  }

  Future<AiCaptureSession> dismissSession(
    String captureId, {
    String? reason,
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final session = await _requireLocalCore().dismissCaptureSession({
        'capture_id': captureId,
        'reason': ?reason,
      }, LocalCoreContext.flutterUser());
      return _sessionFromLocal(session);
    }
    final data = await api.post(
      '/mcp/capture/sessions/$captureId/dismiss',
      data: {'reason': ?reason},
    );
    return AiCaptureSession.fromJson(data);
  }

  Future<AiCaptureCommitResult> commit({
    required String captureId,
    required List<int> selectedActionIndexes,
    String? turnId,
  }) async {
    if (dataMode == LiflyDataMode.local) {
      final result = await _requireLocalCore().captureCommit({
        'capture_id': captureId,
        'selected_action_indexes': selectedActionIndexes,
        'turn_id': ?turnId,
      }, LocalCoreContext.flutterUser());
      return _commitResultFromLocal(
        result,
        captureId: captureId,
        turnId: turnId,
      );
    }

    final data = await api.post(
      '/mcp/capture/commit',
      data: {
        'capture_id': captureId,
        'selected_action_indexes': selectedActionIndexes,
        'turn_id': ?turnId,
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
    final actionTurns = session.turns
        .where((turn) => turn.role == 'assistant' && turn.actions.isNotEmpty)
        .toList();
    return AiCaptureParseResult(
      captureId: session.captureId,
      actions: session.actions.map(_actionFromLocal).toList(growable: false),
      requiresConfirmation: session.requiresConfirmation,
      turnId: actionTurns.isEmpty ? null : actionTurns.last.id,
    );
  }

  AiCaptureSession _sessionFromLocal(LocalCaptureSession session) {
    return AiCaptureSession(
      captureId: session.captureId,
      originalText: session.originalText,
      timezone: session.timezone,
      locale: session.locale,
      actions: session.actions.map(_actionFromLocal).toList(growable: false),
      requiresConfirmation: session.requiresConfirmation,
      committed: session.committed,
      sessionStatus: session.sessionStatus,
      sourceChannel: session.sourceChannel,
      expiresAt: session.expiresAt,
      committedAt: session.committedAt,
      dismissedAt: session.dismissedAt,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      turnCount: session.turns.length,
      turns: session.turns.map(_turnFromLocal).toList(growable: false),
    );
  }

  AiCaptureTurn _turnFromLocal(LocalCaptureTurn turn) {
    return AiCaptureTurn(
      id: turn.id,
      captureId: turn.captureId,
      turnIndex: turn.turnIndex,
      role: turn.role,
      text: turn.text,
      assetIds: turn.assetIds,
      actions: turn.actions.map(_actionFromLocal).toList(growable: false),
      selectedActionIndexes: turn.selectedActionIndexes,
      resultEntities: turn.resultEntities.map(_entityFromLocal).toList(),
      undoToken: turn.undoToken,
      supersedesTurnId: turn.supersedesTurnId,
      turnStatus: turn.turnStatus,
      createdAt: turn.createdAt,
      updatedAt: turn.updatedAt,
    );
  }

  AiCaptureAction _actionFromLocal(LocalCaptureAction action) {
    return AiCaptureAction(
      type: action.type,
      payload: Map<String, dynamic>.from(action.payload),
      confidence: action.confidence,
      rawText: action.rawText,
    );
  }

  AiCaptureCommitResult _commitResultFromLocal(
    LocalCaptureCommitResult result, {
    required String captureId,
    String? turnId,
  }) {
    return AiCaptureCommitResult(
      committed: result.committed,
      createdEntities: result.createdEntities.map(_entityFromLocal).toList(),
      failedActions: const [],
      undoToken: result.undoToken,
      captureId: captureId,
      turnId: turnId,
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
