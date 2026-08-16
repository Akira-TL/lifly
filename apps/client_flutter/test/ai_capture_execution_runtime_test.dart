import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_repository.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_execution_runtime.dart';
import 'package:client_flutter/features/ai_capture/data/lifly_cloud_ai_provider.dart';
import 'package:client_flutter/features/ai_capture/models/cloud_ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySessionStore implements AuthSessionStore {
  _MemorySessionStore(this.value);

  AuthSession? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<AuthSession?> read() async => value;

  @override
  Future<String?> readAccessToken() async => value?.accessToken;

  @override
  Future<void> write(AuthSession session) async => value = session;
}

class _DeviceTransport implements DeviceTransport {
  _DeviceTransport(this.devices);

  final List<Map<String, dynamic>> devices;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    expect(path, '/devices');
    return {'devices': devices};
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? data}) {
    throw UnimplementedError();
  }
}

class _CloudTransport implements CloudAiTransport {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> plan(Map<String, dynamic> body) async {
    calls += 1;
    return {
      'request_id': body['request_id'],
      'provider': 'ollama',
      'model': 'demo-model',
      'actions': [
        {
          'type': 'memo_create',
          'payload': {'type': 'memo', 'content_markdown': '云端候选'},
          'confidence': 0.9,
        },
      ],
    };
  }
}

class _OfflineComputeClient implements ComputeNodePlanClient {
  int calls = 0;

  @override
  Future<ExternalAiPlanResult> plan({
    required AuthSession session,
    required DeviceDescriptor target,
    required String text,
    required List<String> assetIds,
    required String timezone,
    required String locale,
  }) async {
    calls += 1;
    throw const ComputeNodeUnavailable('desktop offline');
  }
}

class _RecordingComputeClient implements ComputeNodePlanClient {
  DeviceDescriptor? target;
  String? timezone;
  String? locale;

  @override
  Future<ExternalAiPlanResult> plan({
    required AuthSession session,
    required DeviceDescriptor target,
    required String text,
    required List<String> assetIds,
    required String timezone,
    required String locale,
  }) async {
    this.target = target;
    this.timezone = timezone;
    this.locale = locale;
    return ExternalAiPlanResult(
      sourceLabel: 'Desktop',
      targetDeviceId: target.deviceId,
      actions: const [],
    );
  }
}

Map<String, dynamic> _deviceJson({
  required String id,
  required bool isDefault,
  required List<String> capabilities,
  String? publicKey,
  int keyVersion = 1,
}) => {
  'device_id': id,
  'account_id': 'account-1',
  'display_name': id == 'desktop-1' ? 'Desktop' : 'Phone',
  'platform': id == 'desktop-1' ? 'linux' : 'android',
  'public_key': publicKey ?? '$id-public-key',
  'trust_state': 'trusted',
  'capability_report': {
    'protocol_version': 1,
    'capabilities': capabilities,
    'supported_tools': <String>[],
  },
  'is_default_compute_node': isDefault,
  'last_seen_at': '2026-08-15T11:30:00Z',
  'key_version': keyVersion,
  'protocol_version': 1,
};

AuthSession _session() => AuthSession(
  account: const AccountProfile(
    accountId: 'account-1',
    phoneE164: '+8613800138000',
    displayName: 'Demo',
    accountStatus: 'active',
    plan: 'demo',
  ),
  device: DeviceDescriptor.fromJson(
    _deviceJson(id: 'phone-1', isDefault: false, capabilities: const []),
  ),
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2026, 8, 16),
  refreshExpiresAt: DateTime.utc(2026, 9, 15),
);

void main() {
  test('loads the trusted default local-ai compute node', () async {
    final cloud = _CloudTransport();
    final runtime = DefaultAiCaptureExecutionRuntime.forTesting(
      sessions: _MemorySessionStore(_session()),
      devices: DeviceRepository(
        _DeviceTransport([
          _deviceJson(id: 'phone-1', isDefault: false, capabilities: const []),
          _deviceJson(
            id: 'desktop-1',
            isDefault: true,
            capabilities: const ['local_ai', 'local_mcp'],
          ),
        ]),
      ),
      cloud: LiflyCloudAiProvider(transport: cloud),
      compute: _OfflineComputeClient(),
    );

    final snapshot = await runtime.loadTargets();

    expect(snapshot.defaultComputeNode?.deviceId, 'desktop-1');
    expect(snapshot.computeNodes.map((item) => item.deviceId), ['desktop-1']);
  });

  test(
    'offline compute failure never invokes Cloud AI automatically',
    () async {
      final cloud = _CloudTransport();
      final compute = _OfflineComputeClient();
      final runtime = DefaultAiCaptureExecutionRuntime.forTesting(
        sessions: _MemorySessionStore(_session()),
        devices: DeviceRepository(
          _DeviceTransport([
            _deviceJson(
              id: 'desktop-1',
              isDefault: true,
              capabilities: const ['local_ai'],
            ),
          ]),
        ),
        cloud: LiflyCloudAiProvider(transport: cloud),
        compute: compute,
      );
      final target = (await runtime.loadTargets()).defaultComputeNode!;

      await expectLater(
        runtime.planOnComputeNode(target: target, text: '记录一条备忘'),
        throwsA(isA<ComputeNodeUnavailable>()),
      );

      expect(compute.calls, 1);
      expect(cloud.calls, 0);
    },
  );

  test(
    'compute planning refreshes a rotated target public key before encryption',
    () async {
      final devices = <Map<String, dynamic>>[
        _deviceJson(
          id: 'desktop-1',
          isDefault: true,
          capabilities: const ['local_ai'],
          publicKey: 'old-public-key',
          keyVersion: 1,
        ),
      ];
      final compute = _RecordingComputeClient();
      final runtime = DefaultAiCaptureExecutionRuntime.forTesting(
        sessions: _MemorySessionStore(_session()),
        devices: DeviceRepository(_DeviceTransport(devices)),
        cloud: LiflyCloudAiProvider(transport: _CloudTransport()),
        compute: compute,
      );
      final staleTarget = (await runtime.loadTargets()).defaultComputeNode!;
      devices[0] = _deviceJson(
        id: 'desktop-1',
        isDefault: true,
        capabilities: const ['local_ai'],
        publicKey: 'rotated-public-key',
        keyVersion: 2,
      );

      await runtime.planOnComputeNode(
        target: staleTarget,
        text: '记录一条备忘',
        timezone: 'America/Los_Angeles',
        locale: 'en-US',
      );

      expect(staleTarget.publicKey, 'old-public-key');
      expect(compute.target?.publicKey, 'rotated-public-key');
      expect(compute.target?.keyVersion, 2);
      expect(compute.timezone, 'America/Los_Angeles');
      expect(compute.locale, 'en-US');
    },
  );

  test('Cloud AI sends only the explicitly disclosed current input', () async {
    final cloud = _CloudTransport();
    final runtime = DefaultAiCaptureExecutionRuntime.forTesting(
      sessions: _MemorySessionStore(_session()),
      devices: DeviceRepository(_DeviceTransport(const [])),
      cloud: LiflyCloudAiProvider(transport: cloud),
      compute: const UnavailableComputeNodePlanClient(),
    );
    final request = CloudAiInferenceRequest(
      requestId: 'request-1',
      disclosure: CloudAiDisclosureScope(
        consentId: 'consent-1',
        granted: true,
        provider: AiProviderKind.ollama,
        model: 'demo-model',
        allowedDataTypes: {'capture_input'},
        reason: '用户本次明确授权 Cloud AI 处理当前输入',
        includesAttachments: false,
        includesHistory: false,
      ),
      input: const AiContextItem(dataType: 'capture_input', content: '记录一条备忘'),
    );

    final result = await runtime.planOnCloud(request);

    expect(cloud.calls, 1);
    expect(result.actions.single.type, 'memo_create');
  });
}
