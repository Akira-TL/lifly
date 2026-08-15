import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/features/ai_capture/data/external_ai_action_committer.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements ExternalAiActionTransport {
  final List<(String, Map<String, dynamic>)> posts = [];

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    posts.add((path, data ?? const {}));
    if (path == '/mcp/capture/undo') {
      return {
        'undone': 1,
        'entities': [
          {'type': 'memo', 'id': 'memo-1'},
        ],
        'failed_entities': <Object>[],
      };
    }
    return {'memo_id': 'memo-1', 'undo_token': 'undo-1'};
  }
}

void main() {
  test(
    'commits a confirmed candidate through existing MCP validation path',
    () async {
      final transport = _Transport();
      final committer = ExternalAiActionCommitter(transport);
      const action = MemoCreateCandidateAction(
        memoType: 'memo',
        contentMarkdown: '云端生成的候选备忘',
        confidence: 0.9,
        rawText: '记录这件事',
      );

      final result = await committer.commit(action);

      expect(result.undoToken, 'undo-1');
      expect(result.entityType, 'memo');
      expect(result.entityId, 'memo-1');
      expect(transport.posts.single.$1, '/mcp/memo/create');
      expect(
        transport.posts.single.$2,
        containsPair('content_markdown', '云端生成的候选备忘'),
      );
    },
  );

  test('undo uses the existing capture undo token mechanism', () async {
    final transport = _Transport();
    final committer = ExternalAiActionCommitter(transport);

    final result = await committer.undo('undo-1');

    expect(result.undone, 1);
    expect(transport.posts.single.$1, '/mcp/capture/undo');
    expect(transport.posts.single.$2, {'undo_token': 'undo-1'});
  });
}
