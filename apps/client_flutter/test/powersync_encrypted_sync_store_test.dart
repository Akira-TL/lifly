import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/account_data_key_ring.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/crypto/encrypted_payload_cipher.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';
import 'package:client_flutter/data/powersync/plaintext_e2ee_migrator.dart';
import 'package:client_flutter/data/powersync/powersync_crud_mapper.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/powersync_persistence_harness.dart';

void main() {
  late PowerSyncPersistenceHarness harness;
  SyncService? syncService;
  late AccountDataKey dataKey;
  late AccountDataKeyRing keyRing;
  PowerSyncEncryptedSyncStore? encryptedStore;

  setUp(() async {
    harness = await PowerSyncPersistenceHarness.create('lifly-e2ee-sync-');
    final opened = await harness.openService();
    syncService = opened;
    if (opened == null) return;
    dataKey = AccountDataKey.fromBytes(
      keyVersion: 1,
      bytes: List<int>.generate(32, (index) => index + 1),
    );
    keyRing = AccountDataKeyRing(dataKey);
    encryptedStore = PowerSyncEncryptedSyncStore(
      db: opened.db,
      accountId: 'account-1',
      keyRing: keyRing,
    );
  });

  tearDown(() async {
    syncService?.dispose();
    await harness.dispose();
  });

  test('putEncryptedEntity keeps plaintext only in local projection', () async {
    final service = syncService;
    final store = encryptedStore;
    if (service == null || store == null) return;
    const secretTitle = '仅本机可见标题';
    const secretBody = 'cloud must not see this body';

    final envelope = await store.putEncryptedEntity(
      DecryptedSyncEntity(
        id: 'memo-1',
        userId: 'account-1',
        entityType: 'memo',
        revision: 1,
        lifecycleStatus: EncryptedEntityLifecycleStatus.active,
        updatedAt: DateTime.utc(2026, 8, 15, 10),
        payload: const {
          'type': 'memo',
          'title': secretTitle,
          'content_markdown': secretBody,
          'tags': ['e2ee'],
          'source': 'flutter',
          'status': 'active',
          'created_at': '2026-08-15T10:00:00.000Z',
        },
      ),
    );

    final encrypted = await service.db.getOptional(
      'SELECT * FROM encrypted_entities WHERE id = ?',
      ['memo-1'],
    );
    final projected = await service.db.getOptional(
      'SELECT title, content_markdown, revision FROM memos WHERE id = ?',
      ['memo-1'],
    );

    expect(encrypted, isNotNull);
    expect(encrypted!.keys, isNot(contains('title')));
    expect(encrypted.keys, isNot(contains('content_markdown')));
    expect(encrypted['ciphertext'].toString(), isNot(contains(secretBody)));
    expect(projected!['title'], secretTitle);
    expect(projected['content_markdown'], secretBody);
    expect(projected['revision'], 1);
    expect(envelope.keyVersion, 1);
  });

  test(
    'applyRemoteEnvelope materializes newer revisions and tombstones',
    () async {
      final service = syncService;
      final store = encryptedStore;
      if (service == null || store == null) return;
      final cipher = EncryptedPayloadCipher();
      final revision2 = await cipher.encryptEntity(
        key: dataKey,
        id: 'memo-remote',
        userId: 'account-1',
        entityType: 'memo',
        revision: 2,
        lifecycleStatus: EncryptedEntityLifecycleStatus.active,
        updatedAt: DateTime.utc(2026, 8, 15, 11),
        payload: const {
          'type': 'memo',
          'title': 'remote title',
          'content_markdown': 'remote secret',
          'status': 'active',
        },
      );
      final first = await store.applyRemoteEnvelope(revision2);
      final stale = await store.applyRemoteEnvelope(revision2);

      expect(first.applied, isTrue);
      expect(stale.applied, isFalse);
      expect(stale.reason, 'stale_revision');
      final projected = await service.db.getOptional(
        'SELECT title, revision FROM memos WHERE id = ?',
        ['memo-remote'],
      );
      expect(projected!['title'], 'remote title');
      expect(projected['revision'], 2);

      final tombstone = await cipher.encryptEntity(
        key: dataKey,
        id: 'memo-remote',
        userId: 'account-1',
        entityType: 'memo',
        revision: 3,
        lifecycleStatus: EncryptedEntityLifecycleStatus.tombstone,
        updatedAt: DateTime.utc(2026, 8, 15, 12),
        payload: const {},
      );
      final removed = await store.applyRemoteEnvelope(tombstone);

      expect(removed.applied, isTrue);
      expect(
        await service.db.getOptional('SELECT id FROM memos WHERE id = ?', [
          'memo-remote',
        ]),
        isNull,
      );
    },
  );

  test(
    'rotateKey re-encrypts active envelopes with a newer ADK version',
    () async {
      final service = syncService;
      final store = encryptedStore;
      if (service == null || store == null) return;
      await store.putEncryptedEntity(
        DecryptedSyncEntity(
          id: 'memo-rotate',
          userId: 'account-1',
          entityType: 'memo',
          revision: 1,
          lifecycleStatus: EncryptedEntityLifecycleStatus.active,
          updatedAt: DateTime.utc(2026, 8, 15, 10),
          payload: const {
            'type': 'memo',
            'title': 'rotate me',
            'content_markdown': 'rotation secret',
            'status': 'active',
          },
        ),
      );
      final before = await service.db.getOptional(
        'SELECT ciphertext FROM encrypted_entities WHERE id = ?',
        ['memo-rotate'],
      );
      final nextKey = AccountDataKey.fromBytes(
        keyVersion: 2,
        bytes: List<int>.generate(32, (index) => 200 - index),
      );

      final result = await store.rotateKey(nextKey);
      final after = await service.db.getOptional(
        'SELECT revision, key_version, ciphertext FROM encrypted_entities WHERE id = ?',
        ['memo-rotate'],
      );

      expect(result.rotated, 1);
      expect(result.skipped, 0);
      expect(result.keyVersion, 2);
      expect(keyRing.current.keyVersion, 2);
      expect(after!['revision'], 2);
      expect(after['key_version'], 2);
      expect(after['ciphertext'], isNot(before!['ciphertext']));
    },
  );

  test('plaintext migration is idempotent and queues only ciphertext', () async {
    final service = syncService;
    final store = encryptedStore;
    if (service == null || store == null) return;
    const secret = 'legacy plaintext should not enter the upload payload';
    await service.db.execute(
      'INSERT INTO memos('
      'id, user_id, type, title, content_markdown, source, status, created_at, updated_at, revision'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'memo-legacy',
        'account-1',
        'memo',
        'legacy',
        secret,
        'flutter',
        'active',
        '2026-08-15T09:00:00.000Z',
        '2026-08-15T10:00:00.000Z',
        4,
      ],
    );
    expect(
      await service.db.getCrudBatch(),
      isNull,
      reason: 'local-only projection writes must not enter PowerSync CRUD',
    );

    final migrator = PlaintextE2eeMigrator(
      db: service.db,
      store: store,
      accountId: 'account-1',
    );
    final first = await migrator.migrateCoreEntities();
    final second = await migrator.migrateCoreEntities();

    expect(first.encrypted, 1);
    expect(second.encrypted, 0);
    expect(second.skipped, greaterThanOrEqualTo(1));

    final batch = await service.db.getCrudBatch();
    expect(batch, isNotNull);
    expect(batch!.crud, isNotEmpty);
    expect(
      batch.crud.every((entry) => entry.table == 'encrypted_entities'),
      isTrue,
    );
    final request = const PowerSyncCrudMapper().mapBatch(
      batch.crud,
      clientId: 'device-1',
    );
    final uploadText = request.toJson().toString();
    expect(uploadText, isNot(contains(secret)));
    expect(uploadText, isNot(contains('content_markdown')));
    expect(uploadText, contains('ciphertext'));
  });
}
