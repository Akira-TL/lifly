import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/ai/device_ai_job_cipher.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
import 'package:client_flutter/data/device/device_repository.dart';
import 'package:client_flutter/features/ai_capture/data/compute_node_plan_client.dart';
import 'package:client_flutter/features/ai_capture/data/external_ai_action_committer.dart';
import 'package:client_flutter/features/ai_capture/data/lifly_cloud_ai_provider.dart';
import 'package:client_flutter/features/ai_capture/models/cloud_ai_models.dart';

class AiExecutionTargetsSnapshot {
  const AiExecutionTargetsSnapshot({
    required this.computeNodes,
    required this.defaultComputeNode,
  });

  final List<DeviceDescriptor> computeNodes;
  final DeviceDescriptor? defaultComputeNode;
}

class ExternalAiPlanResult {
  const ExternalAiPlanResult({
    required this.sourceLabel,
    required this.actions,
    this.targetDeviceId,
  });

  final String sourceLabel;
  final List<AiCandidateAction> actions;
  final String? targetDeviceId;
}

class ComputeNodeUnavailable implements Exception {
  const ComputeNodeUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ComputeNodePlanClient {
  Future<ExternalAiPlanResult> plan({
    required AuthSession session,
    required DeviceDescriptor target,
    required String text,
    required List<String> assetIds,
  });
}

class UnavailableComputeNodePlanClient implements ComputeNodePlanClient {
  const UnavailableComputeNodePlanClient();

  @override
  Future<ExternalAiPlanResult> plan({
    required AuthSession session,
    required DeviceDescriptor target,
    required String text,
    required List<String> assetIds,
  }) {
    throw const ComputeNodeUnavailable('加密 AI Job 中继尚未接入客户端；不会自动改用 Cloud AI。');
  }
}

class UnavailableAiCaptureExecutionRuntime
    implements AiCaptureExecutionRuntime {
  const UnavailableAiCaptureExecutionRuntime();

  @override
  Future<AiExecutionTargetsSnapshot> loadTargets() async =>
      const AiExecutionTargetsSnapshot(
        computeNodes: [],
        defaultComputeNode: null,
      );

  @override
  Future<ExternalAiPlanResult> planOnComputeNode({
    required DeviceDescriptor target,
    required String text,
    List<String> assetIds = const [],
  }) {
    throw const ComputeNodeUnavailable(
      'Device/Compute 路由当前不可用；不会自动转 Cloud AI。',
    );
  }

  @override
  Future<ExternalAiPlanResult> planOnCloud(CloudAiInferenceRequest request) {
    throw StateError('Cloud AI 路由当前不可用');
  }

  @override
  Future<ExternalAiActionCommitResult> commit(AiCandidateAction action) {
    throw StateError('External AI action commit adapter is unavailable');
  }

  @override
  Future<ExternalAiActionUndoResult> undo(String undoToken) {
    throw StateError('External AI action undo adapter is unavailable');
  }
}

abstract interface class AiCaptureExecutionRuntime {
  Future<AiExecutionTargetsSnapshot> loadTargets();

  Future<ExternalAiPlanResult> planOnComputeNode({
    required DeviceDescriptor target,
    required String text,
    List<String> assetIds,
  });

  Future<ExternalAiPlanResult> planOnCloud(CloudAiInferenceRequest request);

  Future<ExternalAiActionCommitResult> commit(AiCandidateAction action);

  Future<ExternalAiActionUndoResult> undo(String undoToken);
}

class DefaultAiCaptureExecutionRuntime implements AiCaptureExecutionRuntime {
  factory DefaultAiCaptureExecutionRuntime(
    ApiClient api, {
    AuthSessionStore? sessions,
    ComputeNodePlanClient? compute,
  }) {
    final resolvedSessions =
        sessions ?? SecureAuthSessionStore(FlutterSecureSecretStore());
    final resolvedCompute =
        compute ??
        RelayComputeNodePlanClient(
          api: api,
          cipher: DeviceAiJobCipher(
            SecureDeviceIdentityStore(FlutterSecureSecretStore()),
          ),
        );
    return DefaultAiCaptureExecutionRuntime._(
      sessions: resolvedSessions,
      devices: DeviceRepository(ApiClientDeviceTransport(api)),
      cloud: LiflyCloudAiProvider(transport: ApiCloudAiTransport(api)),
      committer: ExternalAiActionCommitter(ApiExternalAiActionTransport(api)),
      compute: resolvedCompute,
      api: api,
    );
  }

  DefaultAiCaptureExecutionRuntime.forTesting({
    required AuthSessionStore sessions,
    required DeviceRepository devices,
    required LiflyCloudAiProvider cloud,
    required ComputeNodePlanClient compute,
    ExternalAiActionCommitter? committer,
  }) : this._(
         sessions: sessions,
         devices: devices,
         cloud: cloud,
         committer: committer,
         compute: compute,
       );

  DefaultAiCaptureExecutionRuntime._({
    required this._sessions,
    required this._devices,
    required this._cloud,
    required this._compute,
    this._committer,
    ApiClient? api,
  }) {
    api?.setAccessTokenProvider(_sessions.readAccessToken);
  }

  final AuthSessionStore _sessions;
  final DeviceRepository _devices;
  final LiflyCloudAiProvider _cloud;
  final ExternalAiActionCommitter? _committer;
  final ComputeNodePlanClient _compute;

  @override
  Future<AiExecutionTargetsSnapshot> loadTargets() async {
    final devices = await _devices.list();
    final computeNodes = devices
        .where(
          (device) =>
              device.trustState == DeviceTrustState.trusted &&
              device.capabilityReport.capabilities.contains(
                DeviceCapability.localAi,
              ),
        )
        .toList(growable: false);
    DeviceDescriptor? defaultComputeNode;
    for (final device in computeNodes) {
      if (device.isDefaultComputeNode) {
        defaultComputeNode = device;
        break;
      }
    }
    return AiExecutionTargetsSnapshot(
      computeNodes: computeNodes,
      defaultComputeNode: defaultComputeNode,
    );
  }

  @override
  Future<ExternalAiPlanResult> planOnComputeNode({
    required DeviceDescriptor target,
    required String text,
    List<String> assetIds = const [],
  }) async {
    if (target.trustState != DeviceTrustState.trusted ||
        !target.capabilityReport.capabilities.contains(
          DeviceCapability.localAi,
        )) {
      throw const ComputeNodeUnavailable('目标设备不是可用的 Trusted Compute Node。');
    }
    final session = await _sessions.read();
    if (session == null) {
      throw const ComputeNodeUnavailable('请先登录账号，再发送跨设备加密 AI Job。');
    }
    // Deliberately no Cloud AI fallback here. Any transport/offline failure is
    // surfaced to the caller so the user remains on the Compute Node route.
    return _compute.plan(
      session: session,
      target: target,
      text: text,
      assetIds: assetIds,
    );
  }

  @override
  Future<ExternalAiPlanResult> planOnCloud(
    CloudAiInferenceRequest request,
  ) async {
    final response = await _cloud.plan(request);
    return ExternalAiPlanResult(
      sourceLabel: 'Cloud AI · ${response.provider.value} / ${response.model}',
      actions: response.actions,
    );
  }

  @override
  Future<ExternalAiActionCommitResult> commit(AiCandidateAction action) {
    final committer = _committer;
    if (committer == null) {
      throw StateError('External AI action commit adapter is unavailable');
    }
    return committer.commit(action);
  }

  @override
  Future<ExternalAiActionUndoResult> undo(String undoToken) {
    final committer = _committer;
    if (committer == null) {
      throw StateError('External AI action commit adapter is unavailable');
    }
    return committer.undo(undoToken);
  }
}
