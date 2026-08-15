import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/api/api_client.dart';

abstract interface class ExternalAiActionTransport {
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data});
}

class ApiExternalAiActionTransport implements ExternalAiActionTransport {
  const ApiExternalAiActionTransport(this.api);

  final ApiClient api;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) => api.post(path, data: data);
}

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

class ExternalAiActionCommitter {
  const ExternalAiActionCommitter(this.transport);

  final ExternalAiActionTransport transport;

  Future<ExternalAiActionCommitResult> commit(AiCandidateAction action) async {
    final path = switch (action.type) {
      'memo_create' => '/mcp/memo/create',
      'task_create' => '/mcp/task/create',
      'expense_create' => '/mcp/expense/create',
      'asset_register_external_url' => '/mcp/asset/register-external-url',
      _ => throw StateError('Unsupported external AI action: ${action.type}'),
    };
    final response = await transport.post(
      path,
      data: {
        ...action.payloadJson,
        if (action.rawText != null && action.rawText!.isNotEmpty)
          'source_text': action.rawText,
      },
    );
    final undoToken = response['undo_token'];
    if (undoToken is! String || undoToken.isEmpty) {
      throw const FormatException(
        'External AI commit did not return undo token',
      );
    }
    final entity = _entityRef(action.type, response);
    return ExternalAiActionCommitResult(
      entityType: entity.$1,
      entityId: entity.$2,
      undoToken: undoToken,
    );
  }

  Future<ExternalAiActionUndoResult> undo(String undoToken) async {
    if (undoToken.isEmpty) {
      throw const FormatException('Undo token is required');
    }
    final response = await transport.post(
      '/mcp/capture/undo',
      data: {'undo_token': undoToken},
    );
    final undone = response['undone'];
    if (undone is! int || undone < 0) {
      throw const FormatException('Invalid external AI undo response');
    }
    return ExternalAiActionUndoResult(undone: undone);
  }

  (String, String) _entityRef(
    String actionType,
    Map<String, dynamic> response,
  ) {
    switch (actionType) {
      case 'memo_create':
        return ('memo', _requiredString(response, 'memo_id'));
      case 'task_create':
        return ('task', _nestedId(response, 'task'));
      case 'expense_create':
        return ('ledger_transaction', _nestedId(response, 'transaction'));
      case 'asset_register_external_url':
        final id = response['asset_id'] ?? response['id'];
        if (id is String && id.isNotEmpty) return ('asset', id);
        final data = response['asset'];
        if (data is Map) {
          final nested = data['id'];
          if (nested is String && nested.isNotEmpty) return ('asset', nested);
        }
        throw const FormatException('External asset commit did not return id');
      default:
        throw StateError('Unsupported external AI action: $actionType');
    }
  }
}

String _nestedId(Map<String, dynamic> response, String key) {
  final value = response[key];
  if (value is Map) {
    final id = value['id'];
    if (id is String && id.isNotEmpty) return id;
  }
  throw FormatException('External AI commit did not return $key id');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string for $key');
}
