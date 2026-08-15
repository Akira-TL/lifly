import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/ai_capture/models/cloud_ai_models.dart';

abstract interface class CloudAiTransport {
  Future<Map<String, dynamic>> plan(Map<String, dynamic> body);
}

class ApiCloudAiTransport implements CloudAiTransport {
  const ApiCloudAiTransport(this.api);

  final ApiClient api;

  @override
  Future<Map<String, dynamic>> plan(Map<String, dynamic> body) {
    return api.post('/ai/cloud/plan', data: body);
  }
}

class LiflyCloudAiProvider {
  const LiflyCloudAiProvider({required this.transport});

  final CloudAiTransport transport;

  Future<CloudAiInferenceResponse> plan(CloudAiInferenceRequest request) async {
    request.validateForSend();
    final response = await transport.plan(request.toJson());
    return CloudAiInferenceResponse.fromJson(response);
  }
}
