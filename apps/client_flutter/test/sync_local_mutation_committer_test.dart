import 'package:client_flutter/data/powersync/local_mutation_committer.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'support/powersync_persistence_harness.dart';

class _FailingCommitter implements LocalMutationCommitter {
  @override
  Future<void> commit(SqliteWriteContext transaction) async {
    throw StateError('seal failed');
  }
}

class _RecordingCommitter implements LocalMutationCommitter {
  @override
  Future<void> commit(SqliteWriteContext transaction) async {
    await transaction.execute(
      'INSERT INTO e2ee_projection_state('
      'id, user_id, entity_type, revision, key_version, lifecycle_status, updated_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'memo-1',
        'account-1',
        'memo',
        1,
        1,
        'active',
        '2026-08-16T08:00:00.000Z',
      ],
    );
  }
}

void main() {
  test(
    'local projection and encrypted commit share one SQLite transaction',
    () async {
      final harness = await PowerSyncPersistenceHarness.create(
        'lifly_mutation_transaction_',
      );
      addTearDown(harness.dispose);
      final service = await harness.openService();
      if (service == null) return;
      addTearDown(service.dispose);

      service.setLocalMutationCommitter(_FailingCommitter());
      await expectLater(
        service.writeLocalTransaction((tx) async {
          await tx.execute(
            'INSERT INTO memos('
            'id, user_id, type, content_markdown, source, status, created_at, updated_at, revision'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              'memo-1',
              'account-1',
              'memo',
              'must roll back',
              'flutter',
              'active',
              '2026-08-16T08:00:00.000Z',
              '2026-08-16T08:00:00.000Z',
              1,
            ],
          );
        }),
        throwsA(isA<StateError>()),
      );
      expect(
        await service.db.getOptional('SELECT id FROM memos WHERE id = ?', [
          'memo-1',
        ]),
        isNull,
      );

      service.setLocalMutationCommitter(_RecordingCommitter());
      await service.writeLocalTransaction((tx) async {
        await tx.execute(
          'INSERT INTO memos('
          'id, user_id, type, content_markdown, source, status, created_at, updated_at, revision'
          ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'memo-1',
            'account-1',
            'memo',
            'commit together',
            'flutter',
            'active',
            '2026-08-16T08:00:00.000Z',
            '2026-08-16T08:00:00.000Z',
            1,
          ],
        );
      });
      expect(
        await service.db.getOptional('SELECT id FROM memos WHERE id = ?', [
          'memo-1',
        ]),
        isNotNull,
      );
      expect(
        await service.db.getOptional(
          'SELECT id FROM e2ee_projection_state WHERE id = ?',
          ['memo-1'],
        ),
        isNotNull,
      );
    },
  );
}
