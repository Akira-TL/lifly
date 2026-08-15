const int liflyAiJobProtocolVersion = 1;

enum AiJobMessageType {
  request('request'),
  result('result');

  const AiJobMessageType(this.value);
  final String value;

  static AiJobMessageType fromValue(String value) =>
      AiJobMessageType.values.firstWhere((item) => item.value == value);
}

class AiJobEnvelope {
  final String jobId;
  final String accountId;
  final String sourceDeviceId;
  final String targetDeviceId;
  final AiJobMessageType messageType;
  final String? correlationId;
  final String idempotencyKey;
  final DateTime expiresAt;
  final int encryptionVersion;
  final String nonce;
  final String ciphertext;

  const AiJobEnvelope({
    required this.jobId,
    required this.accountId,
    required this.sourceDeviceId,
    required this.targetDeviceId,
    required this.messageType,
    this.correlationId,
    required this.idempotencyKey,
    required this.expiresAt,
    required this.encryptionVersion,
    required this.nonce,
    required this.ciphertext,
  });

  factory AiJobEnvelope.fromJson(Map<String, dynamic> json) {
    final protocolVersion = _requiredPositiveInt(json, 'protocol_version');
    if (protocolVersion != liflyAiJobProtocolVersion) {
      throw FormatException('Unsupported AI job protocol: $protocolVersion');
    }
    return AiJobEnvelope(
      jobId: _requiredString(json, 'job_id'),
      accountId: _requiredString(json, 'account_id'),
      sourceDeviceId: _requiredString(json, 'source_device_id'),
      targetDeviceId: _requiredString(json, 'target_device_id'),
      messageType: AiJobMessageType.fromValue(
        _requiredString(json, 'message_type'),
      ),
      correlationId: _nullableString(json['correlation_id']),
      idempotencyKey: _requiredString(json, 'idempotency_key'),
      expiresAt: _requiredAwareDateTime(json, 'expires_at'),
      encryptionVersion: _requiredPositiveInt(json, 'encryption_version'),
      nonce: _requiredString(json, 'nonce'),
      ciphertext: _requiredString(json, 'ciphertext'),
    );
  }

  Map<String, dynamic> toJson() => {
    'protocol_version': liflyAiJobProtocolVersion,
    'job_id': jobId,
    'account_id': accountId,
    'source_device_id': sourceDeviceId,
    'target_device_id': targetDeviceId,
    'message_type': messageType.value,
    if (correlationId != null) 'correlation_id': correlationId,
    'idempotency_key': idempotencyKey,
    'expires_at': _canonicalUtcMilliseconds(expiresAt).toIso8601String(),
    'encryption_version': encryptionVersion,
    'nonce': nonce,
    'ciphertext': ciphertext,
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

DateTime _requiredAwareDateTime(Map<String, dynamic> json, String key) {
  final parsed = DateTime.parse(_requiredString(json, key));
  if (!parsed.isUtc) {
    throw FormatException('Expected timezone-aware datetime for $key');
  }
  return parsed;
}

DateTime _canonicalUtcMilliseconds(DateTime value) =>
    DateTime.fromMillisecondsSinceEpoch(
      value.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );

int _requiredPositiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value > 0) return value;
  throw FormatException('Expected positive integer for $key');
}
