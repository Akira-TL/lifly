import 'dart:convert';

import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';
import 'package:client_flutter/domain/entities/asset.dart';
import 'package:client_flutter/features/asset/data/asset_e2ee_cipher.dart';

class PreparedAssetUpload {
  final EncryptedAssetPayload encrypted;

  const PreparedAssetUpload(this.encrypted);
}

abstract interface class AssetE2eeCoordinator {
  String get accountId;

  Future<PreparedAssetUpload> encryptUpload({
    required String assetId,
    required List<int> plaintext,
  });

  Future<Asset> commitInternalAsset({
    required String assetId,
    required String filename,
    required String assetType,
    required String? mimeType,
    required String storageKey,
    required PreparedAssetUpload prepared,
    required DateTime now,
  });

  Future<Asset> registerExternalAsset({
    required String assetId,
    required String externalUrl,
    required String? externalProvider,
    required String assetType,
    required String? title,
    required DateTime now,
  });

  Future<List<Asset>> listLocal({
    int limit = 20,
    int offset = 0,
    String? kind,
    String? assetType,
  });

  Future<Asset?> getLocal(String assetId);

  Future<List<int>> decryptDownloadedAsset({
    required String assetId,
    required List<int> ciphertext,
  });

  Future<void> trashAsset(String assetId, {required DateTime now});

  Future<void> syncMemoAssetRef({
    required String refId,
    required String memoId,
    required String assetId,
    String refType = 'attachment',
    String? positionHint,
    required DateTime now,
  });

  Future<void> tombstoneMemoAssetRef({
    required String refId,
    required int revision,
    required DateTime now,
  });

  Future<bool> applyRemoteEnvelope(EncryptedEntityEnvelope envelope);
}

class PowerSyncAssetE2eeCoordinator implements AssetE2eeCoordinator {
  final PowerSyncEncryptedSyncStore store;
  final AssetE2eeCipher assetCipher;

  PowerSyncAssetE2eeCoordinator({
    required this.store,
    AssetE2eeCipher? assetCipher,
  }) : assetCipher = assetCipher ?? AssetE2eeCipher();

  @override
  String get accountId => store.accountId;

  @override
  Future<PreparedAssetUpload> encryptUpload({
    required String assetId,
    required List<int> plaintext,
  }) async {
    final encrypted = await assetCipher.encrypt(
      assetId: assetId,
      plaintext: plaintext,
      adk: store.keyRing.current,
    );
    return PreparedAssetUpload(encrypted);
  }

  @override
  Future<Asset> commitInternalAsset({
    required String assetId,
    required String filename,
    required String assetType,
    required String? mimeType,
    required String storageKey,
    required PreparedAssetUpload prepared,
    required DateTime now,
  }) async {
    final payload = <String, Object?>{
      'kind': 'internal',
      'asset_type': assetType,
      'filename': filename,
      'mime_type': mimeType,
      'size_bytes': prepared.encrypted.plaintextSizeBytes,
      'sha256': prepared.encrypted.plaintextSha256,
      'storage_provider': 'minio',
      'storage_key': storageKey,
      'visibility': 'private',
      'sync_status': 'synced',
      'status': 'active',
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
      'wrapped_asset_key': prepared.encrypted.wrappedAssetKey.toJson(),
      'asset_encryption_version': liflyAssetEncryptionVersion,
      'ciphertext_sha256': prepared.encrypted.ciphertextSha256,
      'ciphertext_size_bytes': prepared.encrypted.ciphertextSizeBytes,
      'chunk_count': prepared.encrypted.chunkCount,
    };
    final envelope = await _putEntity(
      id: assetId,
      entityType: 'asset',
      revision: 1,
      now: now,
      payload: payload,
    );
    await _materializeAsset(assetId, payload);
    await _recordProjectionState(envelope);
    return (await getLocal(assetId))!;
  }

  @override
  Future<Asset> registerExternalAsset({
    required String assetId,
    required String externalUrl,
    required String? externalProvider,
    required String assetType,
    required String? title,
    required DateTime now,
  }) async {
    final payload = <String, Object?>{
      'kind': 'external',
      'asset_type': assetType,
      'filename': title,
      'mime_type': null,
      'size_bytes': null,
      'sha256': null,
      'storage_provider': null,
      'storage_key': null,
      'external_url': externalUrl,
      'external_provider': externalProvider,
      'visibility': 'private',
      'sync_status': 'synced',
      'status': 'active',
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    };
    final envelope = await _putEntity(
      id: assetId,
      entityType: 'asset',
      revision: 1,
      now: now,
      payload: payload,
    );
    await _materializeAsset(assetId, payload);
    await _recordProjectionState(envelope);
    return (await getLocal(assetId))!;
  }

  @override
  Future<List<Asset>> listLocal({
    int limit = 20,
    int offset = 0,
    String? kind,
    String? assetType,
  }) async {
    final clauses = <String>['user_id = ?', "status = 'active'"];
    final parameters = <Object?>[accountId];
    if (kind != null && kind.isNotEmpty) {
      clauses.add('kind = ?');
      parameters.add(kind);
    }
    if (assetType != null && assetType.isNotEmpty) {
      clauses.add('asset_type = ?');
      parameters.add(assetType);
    }
    parameters.addAll([limit, offset]);
    final rows = await store.db.getAll(
      'SELECT * FROM assets WHERE ${clauses.join(' AND ')} '
      'ORDER BY updated_at DESC LIMIT ? OFFSET ?',
      parameters,
    );
    return rows.map(_assetFromRow).toList(growable: false);
  }

  @override
  Future<Asset?> getLocal(String assetId) async {
    final row = await store.db.getOptional(
      'SELECT * FROM assets WHERE id = ? AND user_id = ?',
      [assetId, accountId],
    );
    return row == null ? null : _assetFromRow(row);
  }

  @override
  Future<List<int>> decryptDownloadedAsset({
    required String assetId,
    required List<int> ciphertext,
  }) async {
    final envelopeRow = await store.db.getOptional(
      'SELECT id, user_id, entity_type, revision, lifecycle_status, updated_at, '
      'key_version, encryption_version, schema_version, nonce, ciphertext '
      'FROM encrypted_entities WHERE id = ? AND user_id = ?',
      [assetId, accountId],
    );
    if (envelopeRow == null) {
      throw StateError('Encrypted asset metadata is unavailable: $assetId');
    }
    final envelope = _envelopeFromRow(envelopeRow);
    final key = store.keyRing.keyForVersion(envelope.keyVersion);
    if (key == null) {
      throw StateError(
        'Missing ADK version ${envelope.keyVersion} for $assetId',
      );
    }
    final payload = await store.cipher.decryptEntity(envelope, key: key);
    final wrappedRaw = payload['wrapped_asset_key'];
    if (wrappedRaw is! Map) {
      throw const FormatException(
        'Encrypted asset metadata has no wrapped asset key',
      );
    }
    return assetCipher.decrypt(
      assetId: assetId,
      ciphertext: ciphertext,
      wrappedAssetKey: WrappedAssetKey.fromJson(
        Map<String, Object?>.from(wrappedRaw),
      ),
      adk: key,
    );
  }

  @override
  Future<void> trashAsset(String assetId, {required DateTime now}) async {
    final state = await _entityState(assetId);
    final payload = state == null ? <String, Object?>{} : state.payload;
    final envelope = await _putEntity(
      id: assetId,
      entityType: 'asset',
      revision: (state?.revision ?? 0) + 1,
      now: now,
      payload: payload,
      lifecycleStatus: EncryptedEntityLifecycleStatus.tombstone,
    );
    await store.db.execute('DELETE FROM assets WHERE id = ?', [assetId]);
    await _recordProjectionState(envelope);
  }

  @override
  Future<void> syncMemoAssetRef({
    required String refId,
    required String memoId,
    required String assetId,
    String refType = 'attachment',
    String? positionHint,
    required DateTime now,
  }) async {
    final payload = <String, Object?>{
      'memo_id': memoId,
      'asset_id': assetId,
      'ref_type': refType,
      'position_hint': positionHint,
      'created_at': now.toUtc().toIso8601String(),
    };
    final envelope = await _putEntity(
      id: refId,
      entityType: 'memo_asset_ref',
      revision: 1,
      now: now,
      payload: payload,
    );
    await _materializeMemoAssetRef(refId, payload);
    await _recordProjectionState(envelope);
  }

  @override
  Future<void> tombstoneMemoAssetRef({
    required String refId,
    required int revision,
    required DateTime now,
  }) async {
    final envelope = await _putEntity(
      id: refId,
      entityType: 'memo_asset_ref',
      revision: revision,
      now: now,
      payload: const {},
      lifecycleStatus: EncryptedEntityLifecycleStatus.tombstone,
    );
    await store.db.execute('DELETE FROM memo_asset_refs WHERE id = ?', [refId]);
    await _recordProjectionState(envelope);
  }

  @override
  Future<bool> applyRemoteEnvelope(EncryptedEntityEnvelope envelope) async {
    if (envelope.userId != accountId) return false;
    if (envelope.entityType != 'asset' &&
        envelope.entityType != 'memo_asset_ref') {
      return false;
    }
    final current = await store.db.getOptional(
      'SELECT revision FROM e2ee_projection_state WHERE id = ? AND user_id = ?',
      [envelope.id, accountId],
    );
    final currentRevision = _intValue(current?['revision']) ?? 0;
    if (currentRevision >= envelope.revision) return false;

    Map<String, Object?> payload = const {};
    if (envelope.lifecycleStatus == EncryptedEntityLifecycleStatus.active) {
      final key = store.keyRing.keyForVersion(envelope.keyVersion);
      if (key == null) {
        throw StateError(
          'Missing ADK version ${envelope.keyVersion} for ${envelope.id}',
        );
      }
      payload = await store.cipher.decryptEntity(envelope, key: key);
    }

    if (envelope.entityType == 'asset') {
      if (envelope.lifecycleStatus ==
          EncryptedEntityLifecycleStatus.tombstone) {
        await store.db.execute('DELETE FROM assets WHERE id = ?', [
          envelope.id,
        ]);
      } else {
        await _materializeAsset(envelope.id, payload);
      }
    } else {
      if (envelope.lifecycleStatus ==
          EncryptedEntityLifecycleStatus.tombstone) {
        await store.db.execute('DELETE FROM memo_asset_refs WHERE id = ?', [
          envelope.id,
        ]);
      } else {
        await _materializeMemoAssetRef(envelope.id, payload);
      }
    }
    await _recordProjectionState(envelope);
    return true;
  }

  Future<EncryptedEntityEnvelope> _putEntity({
    required String id,
    required String entityType,
    required int revision,
    required DateTime now,
    required Map<String, Object?> payload,
    EncryptedEntityLifecycleStatus lifecycleStatus =
        EncryptedEntityLifecycleStatus.active,
  }) {
    return store.putEncryptedEntity(
      DecryptedSyncEntity(
        id: id,
        userId: accountId,
        entityType: entityType,
        revision: revision,
        lifecycleStatus: lifecycleStatus,
        updatedAt: now.toUtc(),
        payload: payload,
      ),
    );
  }

  Future<_DecryptedEntityState?> _entityState(String id) async {
    final row = await store.db.getOptional(
      'SELECT id, user_id, entity_type, revision, lifecycle_status, updated_at, '
      'key_version, encryption_version, schema_version, nonce, ciphertext '
      'FROM encrypted_entities WHERE id = ? AND user_id = ?',
      [id, accountId],
    );
    if (row == null) return null;
    final envelope = _envelopeFromRow(row);
    final key = store.keyRing.keyForVersion(envelope.keyVersion);
    if (key == null) return null;
    return _DecryptedEntityState(
      revision: envelope.revision,
      payload: await store.cipher.decryptEntity(envelope, key: key),
    );
  }

  Future<void> _materializeAsset(
    String id,
    Map<String, Object?> payload,
  ) async {
    final values = <String, Object?>{
      'user_id': accountId,
      'kind': payload['kind'] ?? 'internal',
      'asset_type': payload['asset_type'] ?? 'file',
      'filename': payload['filename'],
      'mime_type': payload['mime_type'],
      'size_bytes': payload['size_bytes'],
      'sha256': payload['sha256'],
      'storage_provider': payload['storage_provider'],
      'storage_key': payload['storage_key'],
      'external_url': payload['external_url'],
      'external_provider': payload['external_provider'],
      'visibility': payload['visibility'] ?? 'private',
      'sync_status': payload['sync_status'] ?? 'synced',
      'status': payload['status'] ?? 'active',
      'created_at':
          payload['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
      'updated_at':
          payload['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
    };
    await _insertOrUpdate('assets', id, values);
  }

  Future<void> _materializeMemoAssetRef(
    String id,
    Map<String, Object?> payload,
  ) async {
    await _insertOrUpdate('memo_asset_refs', id, {
      'memo_id': payload['memo_id'],
      'asset_id': payload['asset_id'],
      'ref_type': payload['ref_type'] ?? 'attachment',
      'position_hint': payload['position_hint'],
      'created_at':
          payload['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _insertOrUpdate(
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    final existing = await store.db.getOptional(
      'SELECT id FROM $table WHERE id = ?',
      [id],
    );
    final columns = values.keys.toList(growable: false);
    if (existing == null) {
      final placeholders = List.filled(columns.length + 1, '?').join(', ');
      await store.db.execute(
        'INSERT INTO $table(id, ${columns.join(', ')}) VALUES ($placeholders)',
        [id, ...columns.map((column) => _sqliteValue(values[column]))],
      );
      return;
    }
    final assignments = columns.map((column) => '$column = ?').join(', ');
    await store.db.execute('UPDATE $table SET $assignments WHERE id = ?', [
      ...columns.map((column) => _sqliteValue(values[column])),
      id,
    ]);
  }

  Future<void> _recordProjectionState(EncryptedEntityEnvelope envelope) async {
    final values = <String, Object?>{
      'user_id': envelope.userId,
      'entity_type': envelope.entityType,
      'revision': envelope.revision,
      'key_version': envelope.keyVersion,
      'lifecycle_status': envelope.lifecycleStatus.value,
      'updated_at': envelope.updatedAt.toUtc().toIso8601String(),
    };
    await _insertOrUpdate('e2ee_projection_state', envelope.id, values);
  }
}

class _DecryptedEntityState {
  final int revision;
  final Map<String, Object?> payload;

  const _DecryptedEntityState({required this.revision, required this.payload});
}

Asset _assetFromRow(Map<String, Object?> row) {
  return Asset.fromJson({
    'id': row['id'],
    'user_id': row['user_id'],
    'kind': row['kind'],
    'asset_type': row['asset_type'],
    'title': row['filename'],
    'filename': row['filename'],
    'mime_type': row['mime_type'],
    'size_bytes': _intValue(row['size_bytes']),
    'sha256': row['sha256'],
    'storage_provider': row['storage_provider'],
    'storage_key': row['storage_key'],
    'external_url': row['external_url'],
    'external_provider': row['external_provider'],
    'visibility': row['visibility'] ?? 'private',
    'sync_status': row['sync_status'] ?? 'synced',
    'status': row['status'] ?? 'active',
    'created_at': row['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
    'updated_at': row['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
  });
}

EncryptedEntityEnvelope _envelopeFromRow(Map<String, Object?> row) {
  return EncryptedEntityEnvelope.fromJson({
    'schema_version': _intValue(row['schema_version']) ?? 1,
    'id': row['id'],
    'user_id': row['user_id'],
    'entity_type': row['entity_type'],
    'revision': _intValue(row['revision']),
    'lifecycle_status': row['lifecycle_status'],
    'updated_at': row['updated_at'],
    'key_version': _intValue(row['key_version']),
    'encryption_version': _intValue(row['encryption_version']),
    'nonce': row['nonce'],
    'ciphertext': row['ciphertext'],
  });
}

Object? _sqliteValue(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is bool) return value ? 1 : 0;
  if (value is List || value is Map) return jsonEncode(value);
  return value;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
