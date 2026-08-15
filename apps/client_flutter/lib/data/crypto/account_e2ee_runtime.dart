import 'dart:convert';

import 'package:client_flutter/data/auth/auth_repository.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/account_data_key_ring.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/crypto/password_key_envelope_cipher.dart';
import 'package:client_flutter/data/local_core/write/encrypted_audit_payload_protector.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';
import 'package:client_flutter/data/powersync/password_key_envelope_service.dart';
import 'package:client_flutter/data/powersync/plaintext_e2ee_migrator.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:client_flutter/domain/entities/asset.dart';
import 'package:client_flutter/domain/entities/memo.dart';
import 'package:client_flutter/features/asset/data/asset_e2ee_sync_adapter.dart';
import 'package:cryptography/cryptography.dart';

class AccountE2eeRuntime
    implements AssetE2eeCoordinator, AuditPayloadProtector {
  final SyncService syncService;
  final AuthSessionStore sessions;
  final SecretStore secrets;
  final PasswordKeyEnvelopeService passwordEnvelopes;
  final PasswordKeyEnvelopeCipher envelopeCipher;

  PowerSyncEncryptedSyncStore? _store;
  PowerSyncAssetE2eeCoordinator? _assets;

  AccountE2eeRuntime({
    required this.syncService,
    required this.sessions,
    required this.secrets,
    required this.passwordEnvelopes,
    PasswordKeyEnvelopeCipher? envelopeCipher,
  }) : envelopeCipher = envelopeCipher ?? PasswordKeyEnvelopeCipher();

  bool get isUnlocked => _store != null;

  @override
  String get accountId => _requireAssets().accountId;

  Future<bool> restoreFromSession() async {
    final session = await sessions.read();
    if (session == null) {
      _lock();
      return false;
    }
    final key = await _readLocalKey(session.account.accountId);
    if (key == null) {
      _lock();
      return false;
    }
    await _activate(session.account.accountId, key);
    return true;
  }

  Future<void> initializeAfterRegistration(AuthCompletion completion) async {
    final accountId = completion.session.account.accountId;
    final dataKey = await AccountDataKey.generate(keyVersion: 1);
    final envelope = await envelopeCipher.wrap(
      accountId: accountId,
      dataKey: dataKey,
      clientExportKey: SecretKey(completion.exportKey),
    );
    await passwordEnvelopes.store(envelope);
    await _writeLocalKey(accountId, dataKey);
    await _activate(accountId, dataKey);
  }

  Future<void> initializeAfterLogin(AuthCompletion completion) async {
    final accountId = completion.session.account.accountId;
    final envelope = await passwordEnvelopes.fetch();
    if (envelope.accountId != accountId) {
      throw const FormatException('Password Key Envelope account mismatch');
    }
    final dataKey = await envelopeCipher.unwrap(
      envelope,
      clientExportKey: SecretKey(completion.exportKey),
    );
    await _writeLocalKey(accountId, dataKey);
    await _activate(accountId, dataKey);
  }

  Future<void> initializeWithLocalDataKey({
    required String accountId,
    required AccountDataKey dataKey,
  }) async {
    await _writeLocalKey(accountId, dataKey);
    await _activate(accountId, dataKey);
  }

  Future<void> destroyLocalKeyForCurrentSession() async {
    final session = await sessions.read();
    if (session != null) {
      await secrets.delete(_keyStorageKey(session.account.accountId));
    }
    _lock();
  }

  Future<void> _activate(String accountId, AccountDataKey key) async {
    await syncService.ensureInitialized();
    final store = PowerSyncEncryptedSyncStore(
      db: syncService.db,
      accountId: accountId,
      keyRing: AccountDataKeyRing(key),
    );
    await PlaintextE2eeMigrator(
      db: syncService.db,
      store: store,
      accountId: accountId,
    ).migrateCoreEntities();
    _store = store;
    _assets = PowerSyncAssetE2eeCoordinator(store: store);
    syncService.setLocalMutationFlusher(flushLocalProjectionToEncryptedSync);
  }

  Future<void> flushLocalProjectionToEncryptedSync() async {
    final store = _requireStore();
    await PlaintextE2eeMigrator(
      db: syncService.db,
      store: store,
      accountId: store.accountId,
    ).migrateCoreEntities();
  }

  void _lock() {
    syncService.setLocalMutationFlusher(null);
    _assets = null;
    _store = null;
  }

  PowerSyncEncryptedSyncStore _requireStore() {
    final value = _store;
    if (value == null) {
      throw StateError(
        'Account E2EE runtime is locked; authenticate to unlock the Account Data Key',
      );
    }
    return value;
  }

  PowerSyncAssetE2eeCoordinator _requireAssets() {
    final value = _assets;
    if (value == null) {
      throw StateError(
        'Asset E2EE runtime is locked; plaintext attachment fallback is disabled',
      );
    }
    return value;
  }

  Future<void> _writeLocalKey(String accountId, AccountDataKey key) async {
    final bytes = await key.extractBytes();
    await secrets.write(
      _keyStorageKey(accountId),
      jsonEncode({
        'key_version': key.keyVersion,
        'key': base64Url.encode(bytes),
      }),
    );
  }

  Future<AccountDataKey?> _readLocalKey(String accountId) async {
    final raw = await secrets.read(_keyStorageKey(accountId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('ADK record must be an object');
      }
      final version = decoded['key_version'];
      final encoded = decoded['key'];
      if (version is! int ||
          version < 1 ||
          encoded is! String ||
          encoded.isEmpty) {
        throw const FormatException('ADK record is incomplete');
      }
      return AccountDataKey.fromBytes(
        keyVersion: version,
        bytes: base64Url.decode(encoded),
      );
    } on Object {
      await secrets.delete(_keyStorageKey(accountId));
      return null;
    }
  }

  String _keyStorageKey(String accountId) => 'lifly.e2ee.adk.v1.$accountId';

  @override
  Future<void> protect({
    required LocalCoreWriteHandle handle,
    required String auditId,
    required String createdAt,
    required LocalCoreAuditLogInput input,
  }) => EncryptedSyncAuditPayloadProtector(_requireStore()).protect(
    handle: handle,
    auditId: auditId,
    createdAt: createdAt,
    input: input,
  );

  @override
  Future<PreparedAssetUpload> encryptUpload({
    required String assetId,
    required List<int> plaintext,
  }) => _requireAssets().encryptUpload(assetId: assetId, plaintext: plaintext);

  @override
  Future<Asset> commitInternalAsset({
    required String assetId,
    required String filename,
    required String assetType,
    required String? mimeType,
    required String storageKey,
    required PreparedAssetUpload prepared,
    required DateTime now,
  }) => _requireAssets().commitInternalAsset(
    assetId: assetId,
    filename: filename,
    assetType: assetType,
    mimeType: mimeType,
    storageKey: storageKey,
    prepared: prepared,
    now: now,
  );

  @override
  Future<Asset> registerExternalAsset({
    required String assetId,
    required String externalUrl,
    required String? externalProvider,
    required String assetType,
    required String? title,
    required DateTime now,
  }) => _requireAssets().registerExternalAsset(
    assetId: assetId,
    externalUrl: externalUrl,
    externalProvider: externalProvider,
    assetType: assetType,
    title: title,
    now: now,
  );

  @override
  Future<List<Asset>> listLocal({
    int limit = 20,
    int offset = 0,
    String? kind,
    String? assetType,
  }) => _requireAssets().listLocal(
    limit: limit,
    offset: offset,
    kind: kind,
    assetType: assetType,
  );

  @override
  Future<Asset?> getLocal(String assetId) => _requireAssets().getLocal(assetId);

  @override
  Future<List<int>> decryptDownloadedAsset({
    required String assetId,
    required List<int> ciphertext,
  }) => _requireAssets().decryptDownloadedAsset(
    assetId: assetId,
    ciphertext: ciphertext,
  );

  @override
  Future<void> trashAsset(String assetId, {required DateTime now}) =>
      _requireAssets().trashAsset(assetId, now: now);

  @override
  Future<AssetKeyRotationResult> rotateAccountDataKey(
    AccountDataKey nextKey, {
    required DateTime now,
  }) async {
    final result = await _requireAssets().rotateAccountDataKey(
      nextKey,
      now: now,
    );
    await _writeLocalKey(accountId, nextKey);
    return result;
  }

  @override
  Future<void> syncMemoAssetRef({
    required String refId,
    required String memoId,
    required String assetId,
    String refType = 'attachment',
    String? positionHint,
    required DateTime now,
  }) => _requireAssets().syncMemoAssetRef(
    refId: refId,
    memoId: memoId,
    assetId: assetId,
    refType: refType,
    positionHint: positionHint,
    now: now,
  );

  @override
  Future<void> tombstoneMemoAssetRef({
    required String refId,
    required int revision,
    required DateTime now,
  }) => _requireAssets().tombstoneMemoAssetRef(
    refId: refId,
    revision: revision,
    now: now,
  );

  @override
  Future<bool> applyRemoteEnvelope(EncryptedEntityEnvelope envelope) =>
      _requireAssets().applyRemoteEnvelope(envelope);

  @override
  Future<List<MemoAssetRef>> listMemoAssetRefs(String memoId) =>
      _requireAssets().listMemoAssetRefs(memoId);

  @override
  Future<void> removeMemoAssetRef({
    required String memoId,
    required String assetId,
    required DateTime now,
  }) => _requireAssets().removeMemoAssetRef(
    memoId: memoId,
    assetId: assetId,
    now: now,
  );
}
