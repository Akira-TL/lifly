import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/write/encrypted_audit_payload_protector.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';
import 'package:client_flutter/data/powersync/local_decrypted_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sensitive audit payload enters encrypted sync seam, never local audit columns',
    () async {
      final syncStore = _RecordingEncryptedSyncStore();
      final writer = LocalCoreAuditLogWriter(
        policy: LocalCoreWritePolicy(),
        payloadProtector: EncryptedSyncAuditPayloadProtector(syncStore),
      );
      final handle = _RecordingWriteHandle();
      final context = LocalCoreContext(
        actorType: LocalCoreActorType.ai,
        sourceChannel: LocalCoreSourceChannel.localMcp,
        userId: 'account-1',
        actorId: 'assistant-1',
        toolName: 'memo_update',
        requestId: 'request-1',
        sourceText: 'private source text',
        now: DateTime.utc(2026, 8, 15, 10),
      );

      await writer.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'memo.update',
          entityType: 'memo',
          entityId: 'memo-1',
          beforeSnapshot: const {'title': 'private old'},
          afterSnapshot: const {'title': 'private new'},
        ),
      );

      final entity = syncStore.entities.single;
      expect(entity.entityType, 'audit');
      expect(entity.userId, 'account-1');
      expect(entity.payload['source_text'], 'private source text');
      expect(entity.payload['before_snapshot'], {'title': 'private old'});
      expect(entity.payload['after_snapshot'], {'title': 'private new'});

      final local = handle.calls.single;
      expect(local.sql, contains('INSERT INTO audit_logs'));
      expect(local.parameters[7], isNull);
      expect(local.parameters[8], isNull);
      expect(local.parameters[10], isNull);
      expect(
        local.parameters.join('|'),
        isNot(contains('private source text')),
      );
      expect(local.parameters.join('|'), isNot(contains('private old')));
      expect(local.parameters.join('|'), isNot(contains('private new')));
    },
  );

  test(
    'default audit writer fails closed instead of persisting sensitive payload',
    () async {
      final writer = LocalCoreAuditLogWriter();
      final handle = _RecordingWriteHandle();
      final context = LocalCoreContext(
        actorType: LocalCoreActorType.user,
        sourceChannel: LocalCoreSourceChannel.flutter,
        userId: 'account-1',
        sourceText: 'must not persist',
        now: DateTime.utc(2026, 8, 15, 10),
      );

      await writer.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'task.update',
          entityType: 'task',
          entityId: 'task-1',
          afterSnapshot: const {'description': 'secret'},
        ),
      );

      final local = handle.calls.single.parameters;
      expect(local[7], isNull);
      expect(local[8], isNull);
      expect(local[10], isNull);
      expect(local.join('|'), isNot(contains('must not persist')));
      expect(local.join('|'), isNot(contains('secret')));
    },
  );
}

class _RecordingEncryptedSyncStore implements EncryptedSyncStore {
  final List<DecryptedSyncEntity> entities = [];

  @override
  Future<EncryptedEntityEnvelope> putEncryptedEntity(
    DecryptedSyncEntity entity,
  ) async {
    entities.add(entity);
    return EncryptedEntityEnvelope(
      id: entity.id,
      userId: entity.userId,
      entityType: entity.entityType,
      revision: entity.revision,
      lifecycleStatus: entity.lifecycleStatus,
      updatedAt: entity.updatedAt,
      keyVersion: 1,
      encryptionVersion: 1,
      nonce: 'bm9uY2U=',
      ciphertext: 'Y2lwaGVydGV4dA==',
    );
  }

  @override
  Future<ProjectionApplyResult> applyRemoteEnvelope(
    EncryptedEntityEnvelope envelope,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<KeyRotationResult> rotateKey(AccountDataKey nextKey) {
    throw UnimplementedError();
  }

  @override
  Stream<EncryptedSyncState> watchSyncState() => const Stream.empty();
}

class _RecordingWriteHandle implements LocalCoreWriteHandle {
  final List<_SqlCall> calls = [];

  @override
  Future<void> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    calls.add(_SqlCall(sql, List<Object?>.from(parameters)));
  }

  @override
  Future<List<Map<String, Object?>>> getAll(
    String sql, [
    List<Object?> parameters = const [],
  ]) async => const [];

  @override
  Future<Map<String, Object?>?> getOptional(
    String sql, [
    List<Object?> parameters = const [],
  ]) async => null;
}

class _SqlCall {
  final String sql;
  final List<Object?> parameters;

  const _SqlCall(this.sql, this.parameters);
}
