import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';

class AiCaptureService {
  const AiCaptureService({
    required this.api,
    required this.dataMode,
    this.localCore,
    this.sessions,
  });

  final ApiClient api;
  final LiflyDataMode dataMode;
  final LocalCoreBridge? localCore;
  final AuthSessionStore? sessions;

  bool get _useLocalCore => localCore != null;

  String get modeLabel {
    return switch (dataMode) {
      LiflyDataMode.api => _useLocalCore ? '本地加密处理' : '云端处理',
      LiflyDataMode.local => localCore == null ? '本地处理不可用' : '本地处理',
    };
  }

  bool get supportsCloudCapture => dataMode == LiflyDataMode.api;

  bool get supportsCapture =>
      dataMode == LiflyDataMode.api || localCore != null;

  Future<List<AiCaptureAssetContext>> listAssets({int limit = 50}) async {
    if (_useLocalCore) {
      final items = await _requireLocalCore().listCaptureAssets({
        'limit': limit,
      }, await _localContext());
      return items.map(_assetContextFromLocal).toList(growable: false);
    }
    final data = await api.get(
      '/assets',
      params: {'limit': limit, 'offset': 0},
    );
    final payload = data['data'];
    final items = payload is Map
        ? payload['items'] as List? ?? const []
        : const [];
    return items
        .whereType<Map>()
        .map(
          (item) => _assetContextFromAssetJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<AiCaptureParseResult> parse({
    required String text,
    String timezone = 'Asia/Shanghai',
    String locale = 'zh-CN',
    List<String> assetIds = const [],
  }) async {
    if (_useLocalCore) {
      final session = await _requireLocalCore().captureParse({
        'text': text,
        'timezone': timezone,
        'locale': locale,
        'asset_ids': assetIds,
      }, await _localContext());
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
    if (_useLocalCore) {
      final items = await _requireLocalCore().listCaptureSessions({
        'status': status,
        'limit': limit,
        'offset': offset,
      }, await _localContext());
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
    if (_useLocalCore) {
      final session = await _requireLocalCore().getCaptureSession({
        'capture_id': captureId,
      }, await _localContext());
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
    if (_useLocalCore) {
      final session = await _requireLocalCore().appendCaptureTurn({
        'capture_id': captureId,
        'text': text,
        'asset_ids': assetIds,
      }, await _localContext());
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
    if (_useLocalCore) {
      final turn = await _requireLocalCore().reviseCaptureAction({
        'capture_id': captureId,
        'turn_id': turnId,
        ...request,
      }, await _localContext());
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
    if (_useLocalCore) {
      final session = await _requireLocalCore().dismissCaptureSession({
        'capture_id': captureId,
        'reason': ?reason,
      }, await _localContext());
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
    if (_useLocalCore) {
      final result = await _requireLocalCore().captureCommit({
        'capture_id': captureId,
        'selected_action_indexes': selectedActionIndexes,
        'turn_id': ?turnId,
      }, await _localContext());
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
    if (_useLocalCore) {
      final result = await _requireLocalCore().captureUndo({
        'undo_token': undoToken,
      }, await _localContext());
      return _undoResultFromLocal(result);
    }

    final data = await api.post(
      '/mcp/capture/undo',
      data: {'undo_token': undoToken},
    );
    return AiCaptureUndoResult.fromJson(data);
  }

  Future<LocalCoreContext> _localContext() async {
    final session = await sessions?.read();
    return LocalCoreContext.flutterUser(
      userId: session?.account.accountId ?? defaultLocalCoreUserId,
    );
  }

  LocalCoreBridge _requireLocalCore() {
    final bridge = localCore;
    if (bridge == null) {
      throw StateError('本地处理不可用，请检查数据模式配置。');
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
      assetContext: actionTurns.isEmpty
          ? const []
          : actionTurns.last.assetContext
                .map(_assetContextFromLocal)
                .toList(growable: false),
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
      assetContext: turn.assetContext
          .map(_assetContextFromLocal)
          .toList(growable: false),
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

  AiCaptureAssetContext _assetContextFromLocal(
    LocalCaptureAssetContext context,
  ) {
    return AiCaptureAssetContext(
      assetId: context.assetId,
      kind: context.kind,
      assetType: context.assetType,
      name: context.name,
      mimeType: context.mimeType,
      sizeBytes: context.sizeBytes,
      sourceUrl: context.sourceUrl,
      status: context.status,
      extractor: context.extractor,
      text: context.text,
      error: context.error,
      requiredCapability: context.requiredCapability,
    );
  }

  AiCaptureAssetContext _assetContextFromAssetJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    final assetType = json['asset_type'] as String?;
    final mimeType = json['mime_type'] as String?;
    final syncStatus = json['sync_status'] as String? ?? 'pending';
    final normalizedMime = (mimeType ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    var status = 'metadata_only';
    var extractor = 'metadata';
    String? requiredCapability = 'binary_content_extractor';
    if (kind == 'internal' && syncStatus != 'synced') {
      status = 'pending_upload';
    } else if (kind == 'external') {
      extractor = 'external_reference';
      requiredCapability = 'external_content_fetch';
    } else if (normalizedMime == 'application/pdf' || assetType == 'pdf') {
      status = 'unsupported';
      extractor = 'pdf_adapter';
      requiredCapability = 'pdf_text_extraction';
    } else if (normalizedMime.startsWith('image/') || assetType == 'image') {
      status = 'unsupported';
      extractor = 'image_adapter';
      requiredCapability = 'ocr_or_vision';
    } else if (normalizedMime.startsWith('audio/') || assetType == 'audio') {
      status = 'unsupported';
      extractor = 'audio_adapter';
      requiredCapability = 'speech_to_text';
    }
    return AiCaptureAssetContext(
      assetId: json['id'] as String? ?? '',
      kind: kind,
      assetType: assetType,
      name:
          json['title'] as String? ??
          json['filename'] as String? ??
          json['external_url'] as String?,
      mimeType: mimeType,
      sizeBytes: json['size_bytes'] as int?,
      sourceUrl: json['external_url'] as String?,
      status: status,
      extractor: extractor,
      error: status == 'pending_upload'
          ? 'asset_sync_status_$syncStatus'
          : null,
      requiredCapability: requiredCapability,
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
