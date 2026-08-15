import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/features/ai_capture/data/lifly_cloud_ai_provider.dart';
import 'package:client_flutter/features/ai_capture/models/cloud_ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'provider config keeps only a secret reference, never the secret value',
    () {
      final config = AiProviderConfig(
        kind: AiProviderKind.openAiCompatible,
        endpoint: Uri.parse('https://provider.example/v1'),
        model: 'compatible-model',
        secretReference: 'secure-store://provider/main',
        privacyBoundary: AiPrivacyBoundary.userEndpoint,
        dataLeavesDevice: true,
      );

      final encoded = config.toJson().toString();
      expect(config.secretReference, 'secure-store://provider/main');
      expect(encoded, isNot(contains('api_key')));
      expect(encoded, isNot(contains('secret_value')));
    },
  );

  test('candidate actions reject unknown types and payload fields', () {
    expect(
      () => AiCandidateAction.fromJson({
        'type': 'unknown_action',
        'payload': <String, dynamic>{},
        'confidence': 0.8,
      }),
      throwsFormatException,
    );

    expect(
      () => AiCandidateAction.fromJson({
        'type': 'task_create',
        'payload': {
          'title': '交报告',
          'priority': 'normal',
          'unexpected': 'fail closed',
        },
        'confidence': 0.8,
      }),
      throwsFormatException,
    );
  });

  test(
    'cloud provider refuses ungranted disclosure before transport',
    () async {
      final transport = _FakeCloudAiTransport();
      final provider = LiflyCloudAiProvider(transport: transport);
      final request = _cloudRequest(granted: false);

      await expectLater(provider.plan(request), throwsStateError);
      expect(transport.calls, 0);
    },
  );

  test('cloud provider sends only the explicit disclosure contract', () async {
    final transport = _FakeCloudAiTransport(
      response: {
        'request_id': 'req-1',
        'provider': 'ollama',
        'model': 'cloud-model',
        'actions': [
          {
            'type': 'task_create',
            'payload': {
              'title': '交报告',
              'remind_at': '2026-08-16T02:00:00Z',
              'priority': 'normal',
            },
            'confidence': 0.95,
          },
        ],
      },
    );
    final provider = LiflyCloudAiProvider(transport: transport);

    final result = await provider.plan(_cloudRequest());

    expect(transport.calls, 1);
    expect(transport.lastBody?['request_id'], 'req-1');
    expect(transport.lastBody?['input'], {
      'data_type': 'user_input',
      'content': '这是本次输入',
    });
    expect(transport.lastBody?['context'], [
      {'data_type': 'memo_excerpt', 'content': '只披露这一段'},
    ]);
    expect(transport.lastBody?['history'], isEmpty);
    expect(transport.lastBody?['attachments'], isEmpty);
    expect(result.actions.single, isA<TaskCreateCandidateAction>());
    expect(result.actions.single.toCaptureAction().type, 'task_create');
  });

  test(
    'cloud disclosure rejects data types outside the approved scope',
    () async {
      final transport = _FakeCloudAiTransport();
      final provider = LiflyCloudAiProvider(transport: transport);
      final request = _cloudRequest().copyWith(
        context: const [
          AiContextItem(dataType: 'ledger_history', content: '未授权数据'),
        ],
      );

      await expectLater(provider.plan(request), throwsStateError);
      expect(transport.calls, 0);
    },
  );
}

CloudAiInferenceRequest _cloudRequest({bool granted = true}) {
  return CloudAiInferenceRequest(
    requestId: 'req-1',
    disclosure: CloudAiDisclosureScope(
      consentId: 'consent-1',
      granted: granted,
      provider: AiProviderKind.ollama,
      model: 'cloud-model',
      allowedDataTypes: const {'user_input', 'memo_excerpt'},
      reason: '根据当前输入生成候选动作',
      includesAttachments: false,
      includesHistory: false,
    ),
    input: const AiContextItem(dataType: 'user_input', content: '这是本次输入'),
    context: const [AiContextItem(dataType: 'memo_excerpt', content: '只披露这一段')],
  );
}

class _FakeCloudAiTransport implements CloudAiTransport {
  _FakeCloudAiTransport({Map<String, dynamic>? response})
    : response =
          response ??
          const {
            'request_id': 'req-1',
            'provider': 'ollama',
            'model': 'cloud-model',
            'actions': <Map<String, dynamic>>[],
          };

  final Map<String, dynamic> response;
  int calls = 0;
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> plan(Map<String, dynamic> body) async {
    calls += 1;
    lastBody = body;
    return response;
  }
}
