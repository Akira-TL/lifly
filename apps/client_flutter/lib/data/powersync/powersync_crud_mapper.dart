import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:powersync/powersync.dart';

class EncryptedSyncPushRequestPayload {
  final String clientId;
  final List<EncryptedEntityEnvelope> changes;
  final int ignoredCount;

  const EncryptedSyncPushRequestPayload({
    required this.clientId,
    required this.changes,
    required this.ignoredCount,
  });

  bool get hasChanges => changes.isNotEmpty;

  int get changeCount => changes.length;

  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'changes': changes.map((change) => change.toJson()).toList(),
  };
}

class PowerSyncCrudMapper {
  const PowerSyncCrudMapper();

  EncryptedSyncPushRequestPayload mapBatch(
    List<CrudEntry> entries, {
    required String clientId,
  }) {
    final changes = <EncryptedEntityEnvelope>[];
    var ignoredCount = 0;
    for (final entry in entries) {
      final change = mapEntry(entry);
      if (change == null) {
        ignoredCount += 1;
      } else {
        changes.add(change);
      }
    }
    return EncryptedSyncPushRequestPayload(
      clientId: clientId,
      changes: changes,
      ignoredCount: ignoredCount,
    );
  }

  EncryptedEntityEnvelope? mapEntry(CrudEntry entry) {
    if (entry.table != 'encrypted_entities') return null;
    if (entry.op == UpdateType.delete) {
      // EncryptedSyncStore represents deletion as a tombstone envelope. A
      // physical DELETE has no ciphertext and must never be converted into a
      // server-side plaintext/implicit delete operation.
      return null;
    }

    final data = <String, dynamic>{
      ...?entry.previousValues,
      ...?entry.opData,
      'id': entry.id,
    };
    return EncryptedEntityEnvelope.fromJson(data);
  }
}
