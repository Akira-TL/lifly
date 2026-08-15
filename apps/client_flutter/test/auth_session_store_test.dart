import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
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

void main() {
  test('secure session store round-trips account device and tokens', () async {
    final secrets = _MemorySecrets();
    final store = SecureAuthSessionStore(secrets);
    final session = AuthSession(
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
        publicKey: 'public-key',
        trustState: DeviceTrustState.trusted,
        capabilityReport: DeviceCapabilityReport(),
        isDefaultComputeNode: false,
      ),
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
      accessExpiresAt: DateTime.utc(2026, 8, 16),
      refreshExpiresAt: DateTime.utc(2026, 9, 15),
    );

    await store.write(session);

    expect(await store.readAccessToken(), 'access-secret');
    final restored = await store.read();
    expect(restored?.account.accountId, 'account-1');
    expect(restored?.device.deviceId, 'device-1');
    expect(restored?.accessToken, 'access-secret');
    expect(restored?.refreshToken, 'refresh-secret');
    expect(secrets.values.values.single, contains('refresh-secret'));

    await store.clear();
    expect(await store.read(), isNull);
    expect(await store.readAccessToken(), isNull);
  });

  test('invalid stored session fails closed and is discarded', () async {
    final secrets = _MemorySecrets();
    final store = SecureAuthSessionStore(secrets);
    await secrets.write('lifly.auth.session.v1', '{not-json');

    expect(await store.read(), isNull);
    expect(secrets.values, isEmpty);
  });
}
