import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/memo/local_memo_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalMemoMapper encodes tags and maps row into LocalMemoRecord', () {
    final createdAt = DateTime.utc(2026, 7, 1, 8);
    final updatedAt = DateTime.utc(2026, 7, 1, 9);

    final memo = LocalMemoMapper.fromRow({
      'id': 'memo_1',
      'type': 'memo',
      'title': 'Local memo',
      'content_markdown': 'memo body',
      'tags': LocalMemoMapper.encodeTags(['local', 'memo']),
      'status': 'active',
      'revision': 2,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    });

    expect(memo.id, 'memo_1');
    expect(memo.tags, ['local', 'memo']);
    expect(memo.revision, 2);
    expect(memo.createdAt, createdAt);
    expect(memo.updatedAt, updatedAt);
  });

  test('LocalMemoMapper creates serializable snapshots', () {
    final memo = LocalMemoRecord(
      id: 'memo_1',
      type: 'memo',
      title: 'Snapshot memo',
      contentMarkdown: 'snapshot body',
      tags: const ['snapshot'],
      status: 'active',
      revision: 1,
      createdAt: DateTime.utc(2026, 7, 1, 8),
      updatedAt: DateTime.utc(2026, 7, 1, 8),
    );

    final snapshot = LocalMemoMapper.snapshot(memo);

    expect(snapshot['id'], 'memo_1');
    expect(snapshot['tags'], ['snapshot']);
    expect(snapshot['created_at'], '2026-07-01T08:00:00.000Z');
  });
}
