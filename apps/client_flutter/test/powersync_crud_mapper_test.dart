import 'package:client_flutter/data/powersync/powersync_crud_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync_sqlcipher/powersync.dart';

void main() {
  const mapper = PowerSyncCrudMapper();

  Map<String, dynamic> encryptedRow({
    int revision = 2,
    String lifecycleStatus = 'active',
  }) {
    return {
      'user_id': 'account-1',
      'entity_type': 'memo',
      'revision': revision,
      'lifecycle_status': lifecycleStatus,
      'updated_at': '2026-08-15T10:00:00.000Z',
      'key_version': 3,
      'encryption_version': 1,
      'schema_version': 1,
      'nonce': 'bm9uY2U=',
      'ciphertext': 'Y2lwaGVydGV4dA==',
    };
  }

  test('maps encrypted entity PUT without exposing plaintext fields', () {
    final entry = CrudEntry(
      1,
      UpdateType.put,
      'encrypted_entities',
      'memo-1',
      null,
      encryptedRow(),
    );

    final request = mapper.mapBatch([entry], clientId: 'device-1');

    expect(request.ignoredCount, 0);
    expect(request.changeCount, 1);
    expect(request.toJson(), {
      'client_id': 'device-1',
      'changes': [
        {
          'schema_version': 1,
          'id': 'memo-1',
          'user_id': 'account-1',
          'entity_type': 'memo',
          'revision': 2,
          'lifecycle_status': 'active',
          'updated_at': '2026-08-15T10:00:00.000Z',
          'key_version': 3,
          'encryption_version': 1,
          'nonce': 'bm9uY2U=',
          'ciphertext': 'Y2lwaGVydGV4dA==',
        },
      ],
    });
    expect(request.toJson().toString(), isNot(contains('title')));
    expect(request.toJson().toString(), isNot(contains('content_markdown')));
    expect(request.toJson().toString(), isNot(contains('amount')));
  });

  test('reconstructs full encrypted envelope from PATCH previous values', () {
    final previous = encryptedRow(revision: 2);
    final entry =
        CrudEntry(2, UpdateType.patch, 'encrypted_entities', 'memo-1', null, {
          'revision': 3,
          'lifecycle_status': 'tombstone',
          'updated_at': '2026-08-15T11:00:00.000Z',
          'nonce': 'bmV3LW5vbmNl',
          'ciphertext': 'bmV3LWNpcGhlcnRleHQ=',
        }, previousValues: previous);

    final change = mapper
        .mapBatch([entry], clientId: 'device-1')
        .changes
        .single;

    expect(change.revision, 3);
    expect(change.lifecycleStatus.value, 'tombstone');
    expect(change.userId, 'account-1');
    expect(change.keyVersion, 3);
    expect(change.ciphertext, 'bmV3LWNpcGhlcnRleHQ=');
  });

  test('ignores local-only plaintext tables', () {
    final entry = CrudEntry(3, UpdateType.put, 'memos', 'memo-1', null, {
      'user_id': 'account-1',
      'title': 'must never upload',
      'content_markdown': 'plaintext',
    });

    final request = mapper.mapBatch([entry], clientId: 'device-1');

    expect(request.hasChanges, isFalse);
    expect(request.ignoredCount, 1);
  });

  test('ignores physical encrypted row DELETE in favor of tombstones', () {
    final entry = CrudEntry(
      4,
      UpdateType.delete,
      'encrypted_entities',
      'memo-1',
      null,
      null,
      previousValues: encryptedRow(),
    );

    final request = mapper.mapBatch([entry], clientId: 'device-1');

    expect(request.hasChanges, isFalse);
    expect(request.ignoredCount, 1);
  });
}
