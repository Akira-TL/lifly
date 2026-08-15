import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:client_flutter/data/ai/ai_job_envelope.dart';
import 'package:client_flutter/data/ai/device_ai_job_cipher.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_repository.dart';
import 'package:client_flutter/data/auth/pake_client_adapter.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_identity_store.dart';
import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/password_key_envelope_cipher.dart';
import 'package:client_flutter/data/powersync/password_key_envelope_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:client_flutter/features/ai_capture/data/compute_node_plan_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecrets implements SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _RecordingRelay implements AiRelayTransport {
  _RecordingRelay(this.inner);

  final AiRelayTransport inner;
  AiJobEnvelope? submitted;

  @override
  Future<AiJobEnvelope?> readResult(String requestJobId) =>
      inner.readResult(requestJobId);

  @override
  Future<AiJobEnvelope> submit(AiJobEnvelope envelope) {
    submitted = envelope;
    return inner.submit(envelope);
  }
}

void main() {
  final runLive = Platform.environment['LIFLY_RUN_GOLDEN_RUNTIME'] == 'true';

  test(
    'live OPAQUE -> two devices -> encrypted relay -> Desktop Ollama -> encrypted result',
    () async {
      final apiBase = _requiredEnv('LIFLY_GOLDEN_API_BASE_URL');
      final helper = _requiredEnv('LIFLY_OPAQUE_CLIENT_HELPER');
      final bridge = _requiredEnv('LIFLY_LOCAL_CORE_BRIDGE_PATH');
      final projectRoot = _requiredEnv('LIFLY_GOLDEN_PROJECT_ROOT');
      final localAiEndpoint = _requiredEnv('LIFLY_LOCAL_AI_ENDPOINT');
      final localAiModel = _requiredEnv('LIFLY_LOCAL_AI_MODEL');
      final bootstrapPath = _requiredEnv('LIFLY_GOLDEN_E2EE_BOOTSTRAP_PATH');
      final phoneDbPath = _requiredEnv('LIFLY_GOLDEN_PHONE_DB_PATH');
      final suffix = (DateTime.now().microsecondsSinceEpoch % 100000000)
          .toString()
          .padLeft(8, '0');
      final phone = '+86138$suffix';
      final password = 'Lifly-Golden-$suffix-安全';
      final phoneDeviceId = 'golden-phone-$suffix';
      final desktopDeviceId = 'golden-desktop-$suffix';

      final phoneSecrets = _MemorySecrets();
      final phoneSessions = SecureAuthSessionStore(phoneSecrets);
      final phoneIdentity = SecureDeviceIdentityStore(
        phoneSecrets,
        newDeviceId: () => phoneDeviceId,
      );
      final phoneApi = ApiClient(
        baseUrl: apiBase,
        accessTokenProvider: phoneSessions.readAccessToken,
      );
      final phoneAuth = AuthRepository(
        ApiClientAuthTransport(phoneApi, phoneSessions),
        phoneSessions,
        phoneIdentity,
        JsonHelperOpaqueClientAdapter(helperPath: helper),
        const DeviceClientProfile(
          displayName: 'Golden Phone',
          platform: 'android',
        ),
      );

      final phoneCompletion = await phoneAuth.register(
        phone: phone,
        password: password,
        displayName: 'Golden Demo',
      );
      final accountDataKey = await AccountDataKey.generate(keyVersion: 1);
      final phoneAdkBytes = List<int>.from(await accountDataKey.extractBytes());
      final passwordEnvelope = await PasswordKeyEnvelopeCipher().wrap(
        accountId: phoneCompletion.session.account.accountId,
        dataKey: accountDataKey,
        clientExportKey: SecretKey(phoneCompletion.exportKey),
      );
      await PasswordKeyEnvelopeService(phoneApi).store(passwordEnvelope);

      final desktopSecrets = _MemorySecrets();
      final desktopSessions = SecureAuthSessionStore(desktopSecrets);
      final desktopIdentity = SecureDeviceIdentityStore(
        desktopSecrets,
        newDeviceId: () => desktopDeviceId,
      );
      final desktopApi = ApiClient(
        baseUrl: apiBase,
        accessTokenProvider: desktopSessions.readAccessToken,
      );
      final desktopAuth = AuthRepository(
        ApiClientAuthTransport(desktopApi, desktopSessions),
        desktopSessions,
        desktopIdentity,
        JsonHelperOpaqueClientAdapter(helperPath: helper),
        const DeviceClientProfile(
          displayName: 'Golden Desktop',
          platform: 'linux',
          capabilityReport: DeviceCapabilityReport(
            capabilities: [
              DeviceCapability.localAi,
              DeviceCapability.localMcp,
              DeviceCapability.backgroundExecutor,
            ],
          ),
          makeDefaultComputeNode: true,
        ),
      );
      final desktopCompletion = await desktopAuth.login(
        phone: phone,
        password: password,
      );
      expect(
        desktopCompletion.session.account.accountId,
        phoneCompletion.session.account.accountId,
      );
      expect(desktopCompletion.exportKey, phoneCompletion.exportKey);
      expect(desktopCompletion.session.device.isDefaultComputeNode, isTrue);
      final fetchedEnvelope = await PasswordKeyEnvelopeService(
        desktopApi,
      ).fetch();
      final desktopDataKey = await PasswordKeyEnvelopeCipher().unwrap(
        fetchedEnvelope,
        clientExportKey: SecretKey(desktopCompletion.exportKey),
      );
      final desktopAdkBytes = List<int>.from(
        await desktopDataKey.extractBytes(),
      );
      expect(desktopAdkBytes, phoneAdkBytes);

      final privateKey = await desktopIdentity.loadPrivateKeyBytes();
      final worker = await Process.start(
        'bash',
        ['scripts/compute-node-start.sh'],
        workingDirectory: projectRoot,
        environment: {
          ...Platform.environment,
          'LIFLY_LOCAL_CORE_BRIDGE_PATH': bridge,
          'LIFLY_API_BASE_URL': apiBase,
          'LIFLY_LOCAL_AI_PROVIDER': 'ollama',
          'LIFLY_LOCAL_AI_ENDPOINT': localAiEndpoint,
          'LIFLY_LOCAL_AI_MODEL': localAiModel,
        },
      );
      final ready = Completer<void>();
      final stdoutLines = <String>[];
      final stderrLines = <String>[];
      final stdoutSub = worker.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            stdoutLines.add(line);
            if (line.contains('encrypted Compute Node worker started') &&
                !ready.isCompleted) {
              ready.complete();
            }
          });
      final stderrSub = worker.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stderrLines.add);

      worker.stdin.writeln(
        jsonEncode({
          'account_id': desktopCompletion.session.account.accountId,
          'account_data_key_base64': base64Encode(desktopAdkBytes),
          'account_data_key_version': desktopDataKey.keyVersion,
          'device_id': desktopDeviceId,
          'private_key_base64': base64Encode(privateKey),
          'access_token': desktopCompletion.session.accessToken,
          'api_base_url': apiBase,
        }),
      );
      await worker.stdin.flush();
      await worker.stdin.close();
      privateKey.fillRange(0, privateKey.length, 0);
      desktopAdkBytes.fillRange(0, desktopAdkBytes.length, 0);

      try {
        await ready.future.timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw StateError(
            'Compute worker did not become ready. stdout=$stdoutLines stderr=$stderrLines',
          ),
        );

        const marker = 'LIFLY_GOLDEN_PRIVATE_MARKER';
        final relay = _RecordingRelay(ApiAiRelayTransport(phoneApi));
        final client = RelayComputeNodePlanClient.forTesting(
          relay: relay,
          cipher: DeviceAiJobCipher(phoneIdentity),
          newJobId: () => 'golden-job-$suffix',
          newIdempotencyKey: () => 'golden-idem-$suffix',
          now: DateTime.now,
          delay: Future<void>.delayed,
          pollInterval: const Duration(milliseconds: 250),
          jobTtl: const Duration(minutes: 2),
          maxPollAttempts: 240,
        );
        final plan = await client.plan(
          session: phoneCompletion.session,
          target: desktopCompletion.session.device,
          text: '请记一条备忘：$marker，今天完成了 Lifly 加密计算节点实机验证。',
          assetIds: const [],
        );

        expect(relay.submitted, isNotNull);
        expect(relay.submitted!.ciphertext, isNot(contains(marker)));
        expect(plan.targetDeviceId, desktopDeviceId);
        expect(plan.actions, isNotEmpty);
        expect(plan.sourceLabel, contains('Golden Desktop'));
        final actionJson = plan.actions.first.toJson();
        expect(jsonEncode(actionJson), contains(marker));
        final bootstrapFile = File(bootstrapPath);
        await bootstrapFile.writeAsString(
          jsonEncode({
            'api_base_url': apiBase,
            'session': phoneCompletion.session.toJson(),
            'account_data_key': base64Url
                .encode(phoneAdkBytes)
                .replaceAll('=', ''),
            'account_data_key_version': accountDataKey.keyVersion,
            'action': actionJson,
            'marker': marker,
            'db_path': phoneDbPath,
          }),
          flush: true,
        );
        final chmod = await Process.run('chmod', ['600', bootstrapPath]);
        if (chmod.exitCode != 0) {
          throw StateError('Unable to protect Golden E2EE bootstrap file');
        }
        phoneAdkBytes.fillRange(0, phoneAdkBytes.length, 0);
        stdout.writeln(
          'GOLDEN_ENCRYPTED_COMPUTE=PASS provider_target=$desktopDeviceId actions=${plan.actions.length}',
        );
      } finally {
        worker.kill(ProcessSignal.sigterm);
        await worker.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            worker.kill(ProcessSignal.sigkill);
            return worker.exitCode;
          },
        );
        await stdoutSub.cancel();
        await stderrSub.cancel();
      }
    },
    skip: runLive ? false : 'Set LIFLY_RUN_GOLDEN_RUNTIME=true',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for the live Golden runtime');
  }
  return value;
}
