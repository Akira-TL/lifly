const int liflyIdentityContractVersion = 1;

class AuthenticatedSubject {
  final String accountId;
  final String? deviceId;

  const AuthenticatedSubject({required this.accountId, this.deviceId});

  String get userId => accountId;

  factory AuthenticatedSubject.fromJson(Map<String, dynamic> json) {
    final accountId = _requiredString(json, 'account_id');
    final claimedUserId = json['user_id'];
    if (claimedUserId != null && claimedUserId != accountId) {
      throw const FormatException(
        'v0.9.0 business user_id must equal authenticated account_id',
      );
    }
    return AuthenticatedSubject(
      accountId: accountId,
      deviceId: _nullableString(json['device_id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'user_id': userId,
    if (deviceId != null) 'device_id': deviceId,
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
