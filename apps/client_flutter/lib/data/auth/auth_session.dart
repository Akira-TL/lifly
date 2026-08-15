import 'package:client_flutter/data/device/device_contracts.dart';

class AccountProfile {
  final String accountId;
  final String phoneE164;
  final String? displayName;
  final String accountStatus;
  final String plan;

  const AccountProfile({
    required this.accountId,
    required this.phoneE164,
    required this.displayName,
    required this.accountStatus,
    required this.plan,
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
    accountId: _requiredString(json, 'account_id'),
    phoneE164: _requiredString(json, 'phone_e164'),
    displayName: _nullableString(json['display_name']),
    accountStatus: _requiredString(json, 'account_status'),
    plan: _requiredString(json, 'plan'),
  );

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'account_id': accountId,
    'phone_e164': phoneE164,
    if (displayName != null) 'display_name': displayName,
    'account_status': accountStatus,
    'plan': plan,
  };
}

class AuthSession {
  final AccountProfile account;
  final DeviceDescriptor device;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  const AuthSession({
    required this.account,
    required this.device,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    account: AccountProfile.fromJson(_requiredMap(json, 'account')),
    device: DeviceDescriptor.fromJson(_requiredMap(json, 'device')),
    accessToken: _requiredString(json, 'access_token'),
    refreshToken: _requiredString(json, 'refresh_token'),
    accessExpiresAt: _requiredDateTime(json, 'access_expires_at'),
    refreshExpiresAt: _requiredDateTime(json, 'refresh_expires_at'),
  );

  Map<String, dynamic> toJson() => {
    'account': account.toJson(),
    'device': device.toJson(),
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': 'bearer',
    'access_expires_at': accessExpiresAt.toUtc().toIso8601String(),
    'refresh_expires_at': refreshExpiresAt.toUtc().toIso8601String(),
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string for $key');
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw const FormatException('Expected null or non-empty string');
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) return value.cast<String, dynamic>();
  throw FormatException('Expected object for $key');
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Expected ISO-8601 timestamp for $key');
  }
  return parsed.toUtc();
}
