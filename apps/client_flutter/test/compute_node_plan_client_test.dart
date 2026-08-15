import 'dart:convert';

import 'package:client_flutter/data/ai/ai_job_envelope.dart';
import 'package:client_flutter/data/ai/device_ai_job_cipher.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
import 'package:client_flutter/features/ai_capture/data/compute_node_plan_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedIdentityStore implements DeviceIdentityStore {
  _FixedIdentityStore({
    required this.deviceId,
    required this.publicKey,
    required this.privateKeyBytes,
  });

  final String deviceId;
  final String publicKey;
  final List<int> privateKeyBytes;

  @override
  Future<DeviceIdentity> loadOrCreate() async =>
      DeviceIdentity(deviceId: deviceId, publicKey: publicKey, keyVersion: 1);

  @override
  Future<List<int>> loadPrivateKeyBytes() async =>
      List<int>.from(privateKeyBytes);
}

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

DeviceDescriptor _descriptor({
  required String deviceId,
  required String publicKey,
  required List<DeviceCapability> capabilities,
}) => DeviceDescriptor(
  deviceId: deviceId,
  accountId: 'account-1',
  displayName: deviceId,
  platform: deviceId == 'phone-1' ? 'android' : 'linux',
  publicKey: publicKey,
  trustState: DeviceTrustState.trusted,
  capabilityReport: DeviceCapabilityReport(capabilities: capabilities),
  isDefaultComputeNode: deviceId == 'desktop-1',
  keyVersion: 1,
  protocolVersion: 1,
);

AuthSession _session(DeviceDescriptor phone) => AuthSession(
  account: const AccountProfile(
    accountId: 'account-1',
    phoneE164: '+8613800138000',
    displayName: 'Demo',
    accountStatus: 'active',
    plan: 'demo',
  ),
  device: phone,
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2026, 8, 16),
  refreshExpiresAt: DateTime.utc(2026, 9, 15),
);

class _LoopbackRelay implements AiRelayTransport {
  _LoopbackRelay({required this.desktopCipher, required this.phonePublicKey});

  final DeviceAiJobCipher desktopCipher;
  final String phonePublicKey;
  AiJobEnvelope? submitted;
  AiJobEnvelope? result;

  @override
  Future<AiJobEnvelope> submit(AiJobEnvelope envelope) async {
    submitted = envelope;
    final clear = await desktopCipher.decryptJson(
      envelope,
      remotePublicKey: phonePublicKey,
    );
    expect(clear, {
      'schema_version': 1,
      'operation': 'plan',
      'text': '记录一下加密中继',
      'asset_ids': ['asset-1'],
    });
    result = await desktopCipher.encryptJson(
      accountId: envelope.accountId,
      sourceDeviceId: envelope.targetDeviceId,
      targetDeviceId: envelope.sourceDeviceId,
      messageType: AiJobMessageType.result,
      correlationId: envelope.jobId,
      jobId: 'result-1',
      idempotencyKey: envelope.idempotencyKey,
      expiresAt: envelope.expiresAt,
      remotePublicKey: phonePublicKey,
      payload: {
        'schema_version': 1,
        'actions': [
          {
            'type': 'memo_create',
            'payload': {'type': 'memo', 'content_markdown': 'Desktop 返回的候选动作'},
            'confidence': 0.91,
          },
        ],
      },
    );
    return envelope;
  }

  @override
  Future<AiJobEnvelope?> readResult(String requestJobId) async {
    expect(requestJobId, 'request-1');
    return result;
  }
}

void main() {
  test(
    'Dart device AI encryption matches independent Node crypto vector',
    () async {
      const desktopPublic = 'zo060cy2M+x7cMF4FKXHbs0CloUFDTRHRboFhw5YfVk=';
      final cipher = DeviceAiJobCipher(
        _FixedIdentityStore(
          deviceId: 'phone-1',
          publicKey: 'pOCSkrZRwni5dyxWn1+puxPZBrRqtoyd+dwrRAn4ogk=',
          privateKeyBytes: List<int>.filled(32, 1),
        ),
        nonce: () => List<int>.filled(12, 5),
      );

      final envelope = await cipher.encryptJson(
        accountId: 'account-1',
        sourceDeviceId: 'phone-1',
        targetDeviceId: 'desktop-1',
        messageType: AiJobMessageType.request,
        jobId: 'request-1',
        idempotencyKey: 'idem-1',
        expiresAt: DateTime.utc(2026, 8, 15, 13),
        remotePublicKey: desktopPublic,
        payload: const {
          'schema_version': 1,
          'operation': 'plan',
          'text': '记一下跨设备',
          'asset_ids': <String>[],
        },
      );

      expect(envelope.nonce, 'BQUFBQUFBQUFBQUF');
      expect(
        envelope.ciphertext,
        '3E2NRilY9tb6-Iz2VJ8lzS_oc7iKfkSzk_x9GGiToztDB4VqdGJYZTZE6wPSD00yehqcsmqOc1qSnDMo6_4Zxkqm0PEsZB_EBnD54hH0lcv5XshXk-cm7VJqQpeAHNNd2NA',
      );
    },
  );

  test(
    'device AI job crypto round trips and binds routing metadata as AAD',
    () async {
      final phoneStore = SecureDeviceIdentityStore(
        _MemorySecrets(),
        newDeviceId: () => 'phone-1',
      );
      final desktopStore = SecureDeviceIdentityStore(
        _MemorySecrets(),
        newDeviceId: () => 'desktop-1',
      );
      final phone = await phoneStore.loadOrCreate();
      final desktop = await desktopStore.loadOrCreate();
      final phoneCipher = DeviceAiJobCipher(phoneStore);
      final desktopCipher = DeviceAiJobCipher(desktopStore);

      final envelope = await phoneCipher.encryptJson(
        accountId: 'account-1',
        sourceDeviceId: 'phone-1',
        targetDeviceId: 'desktop-1',
        messageType: AiJobMessageType.request,
        jobId: 'job-1',
        idempotencyKey: 'idem-1',
        expiresAt: DateTime.utc(2026, 8, 15, 13),
        remotePublicKey: desktop.publicKey,
        payload: const {'secret': 'plaintext-marker'},
      );

      expect(envelope.ciphertext, isNot(contains('plaintext-marker')));
      expect(
        await desktopCipher.decryptJson(
          envelope,
          remotePublicKey: phone.publicKey,
        ),
        const {'secret': 'plaintext-marker'},
      );

      final tampered = AiJobEnvelope(
        jobId: envelope.jobId,
        accountId: envelope.accountId,
        sourceDeviceId: envelope.sourceDeviceId,
        targetDeviceId: 'desktop-2',
        messageType: envelope.messageType,
        correlationId: envelope.correlationId,
        idempotencyKey: envelope.idempotencyKey,
        expiresAt: envelope.expiresAt,
        encryptionVersion: envelope.encryptionVersion,
        nonce: envelope.nonce,
        ciphertext: envelope.ciphertext,
      );
      await expectLater(
        desktopCipher.decryptJson(tampered, remotePublicKey: phone.publicKey),
        throwsA(anything),
      );
    },
  );

  test(
    'real compute node plan client performs encrypted request/result flow',
    () async {
      final phoneIdentityStore = SecureDeviceIdentityStore(
        _MemorySecrets(),
        newDeviceId: () => 'phone-1',
      );
      final desktopIdentityStore = SecureDeviceIdentityStore(
        _MemorySecrets(),
        newDeviceId: () => 'desktop-1',
      );
      final phoneIdentity = await phoneIdentityStore.loadOrCreate();
      final desktopIdentity = await desktopIdentityStore.loadOrCreate();
      final phone = _descriptor(
        deviceId: 'phone-1',
        publicKey: phoneIdentity.publicKey,
        capabilities: const [],
      );
      final desktop = _descriptor(
        deviceId: 'desktop-1',
        publicKey: desktopIdentity.publicKey,
        capabilities: const [
          DeviceCapability.localAi,
          DeviceCapability.localMcp,
        ],
      );
      final relay = _LoopbackRelay(
        desktopCipher: DeviceAiJobCipher(desktopIdentityStore),
        phonePublicKey: phone.publicKey,
      );
      final client = RelayComputeNodePlanClient.forTesting(
        relay: relay,
        cipher: DeviceAiJobCipher(phoneIdentityStore),
        newJobId: () => 'request-1',
        newIdempotencyKey: () => 'idem-1',
        now: () => DateTime.utc(2026, 8, 15, 12),
        delay: (_) async {},
        pollInterval: Duration.zero,
      );

      final planned = await client.plan(
        session: _session(phone),
        target: desktop,
        text: '记录一下加密中继',
        assetIds: const ['asset-1'],
      );

      expect(relay.submitted, isNotNull);
      expect(relay.submitted!.ciphertext, isNot(contains('记录一下加密中继')));
      expect(planned.targetDeviceId, 'desktop-1');
      expect(planned.actions.single.type, 'memo_create');
      expect(
        jsonEncode(planned.actions.single.toJson()),
        contains('Desktop 返回的候选动作'),
      );
    },
  );
}
