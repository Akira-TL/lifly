import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';

class ExternalAiActionCommitResult {
  const ExternalAiActionCommitResult({
    required this.entityType,
    required this.entityId,
    required this.undoToken,
  });

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
    final parsed = await bridge.captureParse({
      'text': _seedText(action),
      'timezone': 'Asia/Shanghai',
      'locale': 'zh-CN',
      'asset_ids': const <String>[],
    }, context);
    final actionTurn = parsed.turns.reversed.firstWhere(
      (turn) => turn.role == 'assistant' && turn.actions.isNotEmpty,
      orElse: () => throw StateError(
        'Local Core could not create a candidate commit seam',
      ),
    );
    final revised = await bridge.reviseCaptureAction({
      'capture_id': parsed.captureId,
      'turn_id': actionTurn.id,
      'action_index': 0,
      'action_type': action.type,
      'payload': action.payloadJson,
      'confidence': action.confidence,
      'note': 'external_ai_candidate',
    }, context);
    final committed = await bridge.captureCommit({
      'capture_id': parsed.captureId,
      'turn_id': revised.id,
      'selected_action_indexes': const [0],
    }, context);
    if (!committed.committed || committed.createdEntities.isEmpty) {
      throw StateError('Local Core did not commit the external AI candidate');
    }
    final entity = committed.createdEntities.first;
    return ExternalAiActionCommitResult(
      entityType: entity.type,
      entityId: entity.id,
      undoToken: committed.undoToken,
    );
  }

  @override
  Future<ExternalAiActionUndoResult> undo(String undoToken) async {
    if (undoToken.isEmpty) {
      throw const FormatException('Undo token is required');
    }
    final result = await bridge.captureUndo({
      'undo_token': undoToken,
    }, await _context());
    return ExternalAiActionUndoResult(undone: result.undone);
  }

  Future<LocalCoreContext> _context() async {
    final session = await sessions.read();
    if (session == null) {
      throw StateError(
        'Account session is required for local AI candidate commit',
      );
    }
    return LocalCoreContext.flutterUser(userId: session.account.accountId);
  }

  String _seedText(AiCandidateAction action) => switch (action) {
    MemoCreateCandidateAction(:final contentMarkdown) => '记一下 $contentMarkdown',
    TaskCreateCandidateAction(:final title) => '提醒我 $title',
    ExpenseCreateCandidateAction(:final amount, :final merchant) =>
      '在${merchant.isEmpty ? '商户' : merchant}花了 $amount',
    AssetRegisterExternalUrlCandidateAction(:final externalUrl) =>
      '保存链接 $externalUrl',
  };
}
