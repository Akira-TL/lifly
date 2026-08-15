import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';

class PasswordKeyEnvelopeService {
  final ApiClient api;

  const PasswordKeyEnvelopeService(this.api);

  Future<PasswordKeyEnvelope> store(PasswordKeyEnvelope envelope) async {
    final response = await api.put(
      '/sync/key-envelope/password',
      data: envelope.toJson(),
    );
    final data = response['data'];
    if (data is! Map) {
      throw const FormatException(
        'Missing password key envelope response data',
      );
    }
    return PasswordKeyEnvelope.fromJson(Map<String, dynamic>.from(data));
  }

  Future<PasswordKeyEnvelope> fetch({int? keyVersion}) async {
    final response = await api.get(
      '/sync/key-envelope/password',
      params: keyVersion == null ? null : {'key_version': keyVersion},
    );
    final data = response['data'];
    if (data is! Map) {
      throw const FormatException(
        'Missing password key envelope response data',
      );
    }
    return PasswordKeyEnvelope.fromJson(Map<String, dynamic>.from(data));
  }
}
