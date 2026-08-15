const int liflyEncryptedEntitySchemaVersion = 1;
const int liflyPasswordKeyEnvelopeSchemaVersion = 1;

enum EncryptedEntityLifecycleStatus {
  active('active'),
  tombstone('tombstone');

  const EncryptedEntityLifecycleStatus(this.value);
  final String value;

  static EncryptedEntityLifecycleStatus fromValue(String value) =>
      EncryptedEntityLifecycleStatus.values.firstWhere(
        (item) => item.value == value,
      );
}

class EncryptedEntityEnvelope {
  final int schemaVersion;
  final String id;
  final String userId;
  final String entityType;
  final int revision;
  final EncryptedEntityLifecycleStatus lifecycleStatus;
  final DateTime updatedAt;
  final int keyVersion;
  final int encryptionVersion;
  final String nonce;
  final String ciphertext;

  const EncryptedEntityEnvelope({
    this.schemaVersion = liflyEncryptedEntitySchemaVersion,
    required this.id,
    required this.userId,
    required this.entityType,
    required this.revision,
    required this.lifecycleStatus,
    required this.updatedAt,
    required this.keyVersion,
    required this.encryptionVersion,
    required this.nonce,
    required this.ciphertext,
  });

  factory EncryptedEntityEnvelope.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requiredPositiveInt(json, 'schema_version');
    if (schemaVersion != liflyEncryptedEntitySchemaVersion) {
      throw FormatException(
        'Unsupported encrypted entity schema: $schemaVersion',
      );
    }
    return EncryptedEntityEnvelope(
      schemaVersion: schemaVersion,
      id: _requiredString(json, 'id'),
      userId: _requiredString(json, 'user_id'),
      entityType: _requiredString(json, 'entity_type'),
      revision: _requiredPositiveInt(json, 'revision'),
      lifecycleStatus: EncryptedEntityLifecycleStatus.fromValue(
        _requiredString(json, 'lifecycle_status'),
      ),
      updatedAt: DateTime.parse(_requiredString(json, 'updated_at')),
      keyVersion: _requiredPositiveInt(json, 'key_version'),
      encryptionVersion: _requiredPositiveInt(json, 'encryption_version'),
      nonce: _requiredString(json, 'nonce'),
      ciphertext: _requiredString(json, 'ciphertext'),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'user_id': userId,
    'entity_type': entityType,
    'revision': revision,
    'lifecycle_status': lifecycleStatus.value,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'key_version': keyVersion,
    'encryption_version': encryptionVersion,
    'nonce': nonce,
    'ciphertext': ciphertext,
  };
}

class PasswordKeyEnvelope {
  final int schemaVersion;
  final String accountId;
  final int keyVersion;
  final int encryptionVersion;
  final String nonce;
  final String ciphertext;

  const PasswordKeyEnvelope({
    this.schemaVersion = liflyPasswordKeyEnvelopeSchemaVersion,
    required this.accountId,
    required this.keyVersion,
    required this.encryptionVersion,
    required this.nonce,
    required this.ciphertext,
  });

  factory PasswordKeyEnvelope.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requiredPositiveInt(json, 'schema_version');
    if (schemaVersion != liflyPasswordKeyEnvelopeSchemaVersion) {
      throw FormatException(
        'Unsupported password envelope schema: $schemaVersion',
      );
    }
    return PasswordKeyEnvelope(
      schemaVersion: schemaVersion,
      accountId: _requiredString(json, 'account_id'),
      keyVersion: _requiredPositiveInt(json, 'key_version'),
      encryptionVersion: _requiredPositiveInt(json, 'encryption_version'),
      nonce: _requiredString(json, 'nonce'),
      ciphertext: _requiredString(json, 'ciphertext'),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'account_id': accountId,
    'key_version': keyVersion,
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

int _requiredPositiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value > 0) return value;
  throw FormatException('Expected positive integer for $key');
}
