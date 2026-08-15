import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';

class EncryptedSyncAuditPayloadProtector implements AuditPayloadProtector {
  final EncryptedSyncStore syncStore;

  const EncryptedSyncAuditPayloadProtector(this.syncStore);

  @override
  Future<void> protect({
    required String auditId,
    required String createdAt,
    required LocalCoreAuditLogInput input,
  }) async {
    final timestamp = DateTime.parse(createdAt).toUtc();
    await syncStore.putEncryptedEntity(
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
  }
}
