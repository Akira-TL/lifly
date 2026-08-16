import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';

class ExternalAiActionCommitResult {
  const ExternalAiActionCommitResult({
    required this.captureId,
    required this.entityType,
    required this.entityId,
    required this.undoToken,
  });

  final String captureId;
  final String entityType;
  final String entityId;
  final String undoToken;
}

class ExternalAiActionUndoResult {
  const ExternalAiActionUndoResult({required this.undone});

  final int undone;
}

abstract interface class ExternalAiActionCommitterContract {
  Future<ExternalAiActionCommitResult> commit(AiCandidateAction action);

  Future<ExternalAiActionUndoResult> undo(String undoToken);
}

class LocalCoreExternalAiActionCommitter
    implements ExternalAiActionCommitterContract {
  const LocalCoreExternalAiActionCommitter({
    required this.bridge,
    required this.sessions,
  });

  final LocalCoreBridge bridge;
  final AuthSessionStore sessions;

  @override
  Future<ExternalAiActionCommitResult> commit(AiCandidateAction action) async {
    final context = await _context();
    final session = await bridge.captureIngestCandidates({
      'source_text': action.rawText ?? '',
      'asset_ids': const <String>[],
      'actions': [action.toJson()],
    }, context);
    final actionTurn = session.turns.reversed.firstWhere(
      (turn) => turn.role == 'assistant' && turn.actions.isNotEmpty,
      orElse: () => throw StateError('本地处理无法创建 AI 执行会话'),
    );
    final committed = await bridge.captureCommit({
      'capture_id': session.captureId,
      'turn_id': actionTurn.id,
      'selected_action_indexes': const [0],
    }, context);
    if (!committed.committed || committed.createdEntities.isEmpty) {
      throw StateError('本地处理未能执行 AI 操作');
    }
    final entity = committed.createdEntities.first;
    return ExternalAiActionCommitResult(
      captureId: session.captureId,
      entityType: entity.type,
      entityId: entity.id,
      undoToken: committed.undoToken,
    );
  }

  @override
  Future<ExternalAiActionUndoResult> undo(String undoToken) async {
    if (undoToken.isEmpty) {
      throw const FormatException('撤回凭据不能为空');
    }
    final result = await bridge.captureUndo({
      'undo_token': undoToken,
    }, await _context());
    return ExternalAiActionUndoResult(undone: result.undone);
  }

  Future<LocalCoreContext> _context() async {
    final session = await sessions.read();
    if (session == null) {
      throw StateError('提交本地 AI 候选动作前需要先登录账号');
    }
    return LocalCoreContext.flutterUser(userId: session.account.accountId);
  }
}
