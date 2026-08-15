import 'package:client_flutter/data/api/api_client.dart';

class LiflyPowerSyncCredentials {
  final String endpoint;
  final String token;
  final String userId;
  final String deviceId;
  final DateTime expiresAt;
  final String mode;

  const LiflyPowerSyncCredentials({
    required this.endpoint,
    required this.token,
    required this.userId,
    required this.deviceId,
    required this.expiresAt,
    required this.mode,
  });

  factory LiflyPowerSyncCredentials.fromJson(Map<String, dynamic> json) {
    return LiflyPowerSyncCredentials(
      endpoint: json['endpoint'] as String? ?? '',
      token: json['token'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      mode: json['mode'] as String? ?? 'authenticated',
    );
  }

  bool get hasToken => token.isNotEmpty;

  String get tokenStatus => hasToken ? '已获取' : '未获取';
}

class PowerSyncCredentialsService {
  final ApiClient api;

  const PowerSyncCredentialsService(this.api);

  Future<LiflyPowerSyncCredentials> fetchCredentials() async {
    final response = await api.get('/sync/credentials');
    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('PowerSync credentials response missing data');
    }
    return LiflyPowerSyncCredentials.fromJson(data);
  }
}
