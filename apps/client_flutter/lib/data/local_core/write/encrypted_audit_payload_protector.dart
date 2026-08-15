import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';

class EncryptedSyncAuditPayloadProtector implements AuditPayloadProtector {
  final EncryptedSyncStore syncStore;

  const EncryptedSyncAuditPayloadProtector(this.syncStore);

  @override
  Future<void> protect({
    required LocalCoreWriteHandle handle,
    required String auditId,
    required String createdAt,
    required LocalCoreAuditLogInput input,
  }) async {
    final timestamp = DateTime.parse(createdAt).toUtc();
    final envelope = await syncStore.sealEntity(
      DecryptedSyncEntity(
        id: auditId,
        userId: input.context.userId,
        entityType: 'audit',
        revision: 1,
        lifecycleStatus: EncryptedEntityLifecycleStatus.active,
        updatedAt: timestamp,
        payload: {
          'actor_type': input.context.actorTypeName,
          'actor_id': input.context.actorId,
          'action': input.action,
          'entity_type': input.entityType,
          'entity_id': input.entityId,
          'before_snapshot': input.beforeSnapshot,
          'after_snapshot': input.afterSnapshot,
          'source_channel': input.context.sourceChannelName,
          'source_text': input.context.sourceText,
          'tool_name': input.context.toolName,
          'request_id': input.context.requestId,
          'created_at': timestamp.toIso8601String(),
        },
      ),
    );
    await handle.execute(
      'INSERT INTO encrypted_entities('
      'id, user_id, entity_type, revision, lifecycle_status, updated_at, '
      'key_version, encryption_version, schema_version, nonce, ciphertext'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        envelope.id,
        envelope.userId,
        envelope.entityType,
        envelope.revision,
        envelope.lifecycleStatus.value,
        envelope.updatedAt.toUtc().toIso8601String(),
        envelope.keyVersion,
        envelope.encryptionVersion,
        liflyEncryptedEntitySchemaVersion,
        envelope.nonce,
        envelope.ciphertext,
      ],
    );
  }
}
