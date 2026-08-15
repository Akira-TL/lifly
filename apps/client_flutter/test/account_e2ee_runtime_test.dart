import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_repository.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/crypto/account_e2ee_runtime.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/password_key_envelope_service.dart';
import 'support/powersync_persistence_harness.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _MemoryPasswordEnvelopeService extends PasswordKeyEnvelopeService {
  _MemoryPasswordEnvelopeService()
    : super(ApiClient(baseUrl: 'http://example.invalid/api/v1'));

  PasswordKeyEnvelope? value;

  @override
  Future<PasswordKeyEnvelope> fetch({int? keyVersion}) async {
    final envelope = value;
    if (envelope == null) throw StateError('Password Key Envelope missing');
    return envelope;
  }

  @override
  Future<PasswordKeyEnvelope> store(PasswordKeyEnvelope envelope) async {
    value = envelope;
    return envelope;
  }
}

AuthSession _session() => AuthSession(
  account: const AccountProfile(
    accountId: 'account-1',
    phoneE164: '+8613800138000',
    displayName: 'Demo',
    accountStatus: 'active',
    plan: 'demo',
  ),
  device: const DeviceDescriptor(
    deviceId: 'device-1',
    accountId: 'account-1',
    displayName: 'Phone',
    platform: 'android',
    publicKey: 'device-public-key',
    trustState: DeviceTrustState.trusted,
    capabilityReport: DeviceCapabilityReport(),
    isDefaultComputeNode: false,
    keyVersion: 1,
    protocolVersion: 1,
  ),
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2026, 8, 16),
  refreshExpiresAt: DateTime.utc(2026, 9, 15),
);

void main() {
  test(
    'registration unlocks shared E2EE runtime and Local Core audit stays ciphertext-only',
    () async {
      final harness = await PowerSyncPersistenceHarness.create(
        'lifly_account_e2ee_',
      );
      addTearDown(harness.dispose);
      final syncService = await harness.openService();
      if (syncService == null) return;
      addTearDown(syncService.dispose);

      const legacySecret = 'legacy plaintext marker must migrate encrypted';
      await syncService.db.execute(
        'INSERT INTO memos('
        'id, user_id, type, title, content_markdown, source, status, created_at, updated_at, revision'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'memo-legacy-runtime',
          'account-1',
          'memo',
          'legacy',
          legacySecret,
          'flutter',
          'active',
          '2026-08-15T09:00:00.000Z',
          '2026-08-15T10:00:00.000Z',
          2,
        ],
      );

      final secrets = _MemorySecrets();
      final sessions = SecureAuthSessionStore(secrets);
      await sessions.write(_session());
      final envelopes = _MemoryPasswordEnvelopeService();
      final runtime = AccountE2eeRuntime(
        syncService: syncService,
        sessions: sessions,
        secrets: secrets,
        passwordEnvelopes: envelopes,
      );
      final completion = AuthCompletion(
        session: _session(),
        exportKey: List<int>.generate(32, (index) => index + 11),
      );

      await runtime.initializeAfterRegistration(completion);

      expect(runtime.isUnlocked, isTrue);
      expect(envelopes.value, isNotNull);
      expect(envelopes.value!.ciphertext, isNotEmpty);
      final migrated = await syncService.db.getOptional(
        "SELECT ciphertext FROM encrypted_entities WHERE id = 'memo-legacy-runtime'",
      );
      expect(migrated, isNotNull);
      expect(migrated!['ciphertext'] as String, isNot(contains(legacySecret)));
      expect(
        secrets.values.values.join('|'),
        isNot(contains('access-via-export-key')),
      );

      final bridge = PowerSyncLocalCoreBridge(
        syncService: syncService,
        auditPayloadProtector: runtime,
      );
      final createdMemo = await bridge.createMemo(
        const {
          'type': 'memo',
          'title': '敏感标题 marker-title',
          'content_markdown': '敏感正文 marker-body',
        },
        const LocalCoreContext(
          actorType: LocalCoreActorType.user,
          sourceChannel: LocalCoreSourceChannel.flutter,
          userId: 'account-1',
          sourceText: '敏感来源 marker-source',
        ),
      );

      final encryptedMemo = await syncService.db.getOptional(
        'SELECT ciphertext FROM encrypted_entities '
        "WHERE id = ? AND entity_type = 'memo'",
        [createdMemo.id],
      );
      expect(encryptedMemo, isNotNull);
      expect(
        encryptedMemo!['ciphertext'] as String,
        isNot(contains('marker-title')),
      );
      expect(
        encryptedMemo['ciphertext'] as String,
        isNot(contains('marker-body')),
      );

      final audit = await syncService.db.getOptional(
        'SELECT before_json, after_json, source_text FROM audit_logs LIMIT 1',
      );
      expect(audit, isNotNull);
      expect(audit!['before_json'], isNull);
      expect(audit['after_json'], isNull);
      expect(audit['source_text'], isNull);

      final encryptedAudit = await syncService.db.getOptional(
        "SELECT ciphertext FROM encrypted_entities WHERE entity_type = 'audit' LIMIT 1",
      );
      expect(encryptedAudit, isNotNull);
      final ciphertext = encryptedAudit!['ciphertext'] as String;
      expect(ciphertext, isNot(contains('marker-title')));
      expect(ciphertext, isNot(contains('marker-body')));
      expect(ciphertext, isNot(contains('marker-source')));
    },
  );

  test(
    'memo-asset refs are encrypted locally and can be listed then tombstoned',
    () async {
      final harness = await PowerSyncPersistenceHarness.create(
        'lifly_asset_ref_e2ee_',
      );
      addTearDown(harness.dispose);
      final syncService = await harness.openService();
      if (syncService == null) return;
      addTearDown(syncService.dispose);

      final secrets = _MemorySecrets();
      final sessions = SecureAuthSessionStore(secrets);
      await sessions.write(_session());
      final envelopes = _MemoryPasswordEnvelopeService();
      final runtime = AccountE2eeRuntime(
        syncService: syncService,
        sessions: sessions,
        secrets: secrets,
        passwordEnvelopes: envelopes,
      );
      await runtime.initializeAfterRegistration(
        AuthCompletion(
          session: _session(),
          exportKey: List<int>.generate(32, (index) => index + 31),
        ),
      );
      final now = DateTime.utc(2026, 8, 15, 12);
      await runtime.registerExternalAsset(
        assetId: 'asset-1',
        externalUrl: 'https://example.invalid/private',
        externalProvider: 'web',
        assetType: 'link',
        title: 'private asset',
        now: now,
      );
      await runtime.syncMemoAssetRef(
        refId: 'ref-1',
        memoId: 'memo-1',
        assetId: 'asset-1',
        now: now,
      );

      final refs = await runtime.listMemoAssetRefs('memo-1');
      expect(refs, hasLength(1));
      expect(refs.single.assetId, 'asset-1');

      final relationEnvelope = await syncService.db.getOptional(
        "SELECT ciphertext FROM encrypted_entities WHERE id = 'ref-1' AND entity_type = 'memo_asset_ref'",
      );
      expect(relationEnvelope, isNotNull);
      expect(
        relationEnvelope!['ciphertext'] as String,
        isNot(contains('memo-1')),
      );

      await runtime.removeMemoAssetRef(
        memoId: 'memo-1',
        assetId: 'asset-1',
        now: now.add(const Duration(minutes: 1)),
      );
      expect(await runtime.listMemoAssetRefs('memo-1'), isEmpty);
    },
  );
}
