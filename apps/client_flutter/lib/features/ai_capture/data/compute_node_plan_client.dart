import 'dart:async';

import 'package:client_flutter/data/ai/ai_job_envelope.dart';
import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/ai/device_ai_job_cipher.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_execution_runtime.dart';
import 'package:uuid/uuid.dart';

abstract interface class AiRelayTransport {
  Future<AiJobEnvelope> submit(AiJobEnvelope envelope);

  Future<AiJobEnvelope?> readResult(String requestJobId);
}

class ApiAiRelayTransport implements AiRelayTransport {
  final ApiClient _api;

  const ApiAiRelayTransport(this._api);

  @override
  Future<AiJobEnvelope> submit(AiJobEnvelope envelope) async =>
      AiJobEnvelope.fromJson(
        await _api.post('/ai/relay/jobs', data: envelope.toJson()),
      );

  @override
  Future<AiJobEnvelope?> readResult(String requestJobId) async {
    final response = await _api.getOptional(
      '/ai/relay/jobs/$requestJobId/result',
    );
    return response == null ? null : AiJobEnvelope.fromJson(response);
  }
}

class RelayComputeNodePlanClient implements ComputeNodePlanClient {
  final AiRelayTransport _relay;
  final DeviceAiJobCipher _cipher;
  final String Function() _newJobId;
  final String Function() _newIdempotencyKey;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final Duration pollInterval;
  final Duration jobTtl;
  final int maxPollAttempts;

  RelayComputeNodePlanClient({
    required ApiClient api,
    required DeviceAiJobCipher cipher,
    Duration pollInterval = const Duration(seconds: 1),
    Duration jobTtl = const Duration(minutes: 2),
    int maxPollAttempts = 120,
  }) : this._(
         relay: ApiAiRelayTransport(api),
         cipher: cipher,
         newJobId: const Uuid().v4,
         newIdempotencyKey: const Uuid().v4,
         now: DateTime.now,
         delay: Future<void>.delayed,
         pollInterval: pollInterval,
         jobTtl: jobTtl,
         maxPollAttempts: maxPollAttempts,
       );

  RelayComputeNodePlanClient.forTesting({
    required AiRelayTransport relay,
    required DeviceAiJobCipher cipher,
    required String Function() newJobId,
    required String Function() newIdempotencyKey,
    required DateTime Function() now,
    required Future<void> Function(Duration) delay,
    Duration pollInterval = const Duration(seconds: 1),
    Duration jobTtl = const Duration(minutes: 2),
    int maxPollAttempts = 120,
  }) : this._(
         relay: relay,
         cipher: cipher,
         newJobId: newJobId,
         newIdempotencyKey: newIdempotencyKey,
         now: now,
         delay: delay,
         pollInterval: pollInterval,
         jobTtl: jobTtl,
         maxPollAttempts: maxPollAttempts,
       );

  RelayComputeNodePlanClient._({
    required this._relay,
    required this._cipher,
    required this._newJobId,
    required this._newIdempotencyKey,
    required this._now,
    required this._delay,
    required this.pollInterval,
    required this.jobTtl,
    required this.maxPollAttempts,
  }) {
    if (maxPollAttempts < 1) {
      throw ArgumentError.value(
        maxPollAttempts,
        'maxPollAttempts',
        'must be positive',
      );
    }
    if (jobTtl <= Duration.zero) {
      throw ArgumentError.value(jobTtl, 'jobTtl', 'must be positive');
    }
  }

  @override
  Future<ExternalAiPlanResult> plan({
    required AuthSession session,
    required DeviceDescriptor target,
    required String text,
    required List<String> assetIds,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw const FormatException('Compute Node AI input must not be empty');
    }
    if (session.account.accountId != target.accountId) {
      throw const ComputeNodeUnavailable('目标 Compute Node 不属于当前 Account。');
    }
    if (session.device.deviceId == target.deviceId) {
      throw const ComputeNodeUnavailable('跨设备 AI Job 不能发送给当前设备自身。');
    }
    if (target.trustState != DeviceTrustState.trusted ||
        !target.capabilityReport.capabilities.contains(
          DeviceCapability.localAi,
        )) {
      throw const ComputeNodeUnavailable('目标设备不是可用的 Trusted Compute Node。');
    }

    final requestJobId = _newJobId();
    final idempotencyKey = _newIdempotencyKey();
    final expiresAt = _now().toUtc().add(jobTtl);
    final request = await _cipher.encryptJson(
      accountId: session.account.accountId,
      sourceDeviceId: session.device.deviceId,
      targetDeviceId: target.deviceId,
      messageType: AiJobMessageType.request,
      jobId: requestJobId,
      idempotencyKey: idempotencyKey,
      expiresAt: expiresAt,
      remotePublicKey: target.publicKey,
      payload: <String, Object?>{
        'schema_version': 1,
        'operation': 'plan',
        'text': normalizedText,
        'asset_ids': List<String>.unmodifiable(assetIds),
      },
    );
    await _relay.submit(request);

    for (var attempt = 0; attempt < maxPollAttempts; attempt += 1) {
      final result = await _relay.readResult(requestJobId);
      if (result != null) {
        return _decodeResult(
          result,
          request: request,
          target: target,
          session: session,
        );
      }
      if (_now().toUtc().isAfter(expiresAt)) {
        break;
      }
      await _delay(pollInterval);
    }
    throw const ComputeNodeUnavailable(
      'Compute Node 暂未返回加密 AI Job 结果；不会自动改用 Cloud AI。',
    );
  }

  Future<ExternalAiPlanResult> _decodeResult(
    AiJobEnvelope result, {
    required AiJobEnvelope request,
    required DeviceDescriptor target,
    required AuthSession session,
  }) async {
    if (result.accountId != session.account.accountId ||
        result.sourceDeviceId != target.deviceId ||
        result.targetDeviceId != session.device.deviceId ||
        result.messageType != AiJobMessageType.result ||
        result.correlationId != request.jobId ||
        result.idempotencyKey != request.idempotencyKey ||
        !result.expiresAt.isAtSameMomentAs(request.expiresAt)) {
      throw const FormatException(
        'Compute Node result envelope does not match request',
      );
    }
    final clear = await _cipher.decryptJson(
      result,
      remotePublicKey: target.publicKey,
    );
    if (clear['schema_version'] != 1) {
      throw const FormatException('Unsupported Compute Node result schema');
    }
    final rawActions = clear['actions'];
    if (rawActions is! List) {
      throw const FormatException(
        'Compute Node result has no candidate actions',
      );
    }
    final actions = rawActions
        .map((item) {
          if (item is! Map) {
            throw const FormatException(
              'Compute Node candidate action must be an object',
            );
          }
          return AiCandidateAction.fromJson(item.cast<String, dynamic>());
        })
        .toList(growable: false);
    return ExternalAiPlanResult(
      sourceLabel: 'Compute Node · ${target.displayName}',
      actions: actions,
      targetDeviceId: target.deviceId,
    );
  }
}
