import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/crypto/encrypted_envelope.dart';
import 'package:client_flutter/data/powersync/password_key_envelope_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePasswordEnvelopeApiClient extends ApiClient {
  final List<Map<String, dynamic>> writes = [];

  FakePasswordEnvelopeApiClient()
    : super(baseUrl: 'http://example.invalid/api/v1');

  @override
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    expect(path, '/sync/key-envelope/password');
    writes.add(Map<String, dynamic>.from(data ?? const {}));
    return {'success': true, 'data': data};
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    expect(path, '/sync/key-envelope/password');
    expect(params, {'key_version': 2});
    return {
      'success': true,
      'data': {
        'schema_version': 1,
        'account_id': 'account-1',
        'key_version': 2,
        'encryption_version': 1,
        'nonce': 'bm9uY2U=',
        'ciphertext': 'd3JhcHBlZC1hZGs=',
      },
    };
  }
}

void main() {
  test('uploads and fetches opaque password key envelopes', () async {
    final api = FakePasswordEnvelopeApiClient();
    final service = PasswordKeyEnvelopeService(api);
    const envelope = PasswordKeyEnvelope(
      accountId: 'account-1',
      keyVersion: 2,
      encryptionVersion: 1,
      nonce: 'bm9uY2U=',
      ciphertext: 'd3JhcHBlZC1hZGs=',
    );

    final stored = await service.store(envelope);
    final fetched = await service.fetch(keyVersion: 2);

    expect(stored.toJson(), envelope.toJson());
    expect(fetched.toJson(), envelope.toJson());
    expect(api.writes.single.keys, isNot(contains('password')));
    expect(api.writes.single.keys, isNot(contains('adk')));
  });
}
