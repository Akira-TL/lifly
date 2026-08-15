const int liflyDeviceProtocolVersion = 1;

enum DeviceCapability {
  localAi('local_ai'),
  localMcp('local_mcp'),
  backgroundExecutor('background_executor');

  const DeviceCapability(this.value);
  final String value;

  static DeviceCapability fromValue(String value) =>
      DeviceCapability.values.firstWhere((item) => item.value == value);
}

enum DeviceTrustState {
  pending('pending'),
  trusted('trusted'),
  revoked('revoked');

  const DeviceTrustState(this.value);
  final String value;

  static DeviceTrustState fromValue(String value) =>
      DeviceTrustState.values.firstWhere((item) => item.value == value);
}

class DeviceCapabilityReport {
  final List<DeviceCapability> capabilities;
  final List<String> supportedTools;

  const DeviceCapabilityReport({
    this.capabilities = const [],
    this.supportedTools = const [],
  });

  factory DeviceCapabilityReport.fromJson(Map<String, dynamic> json) {
    final protocolVersion = json['protocol_version'] as int? ?? 0;
    if (protocolVersion != liflyDeviceProtocolVersion) {
      throw FormatException(
        'Unsupported device protocol version: $protocolVersion',
      );
    }
    return DeviceCapabilityReport(
      capabilities: _stringList(
        json['capabilities'],
      ).map(DeviceCapability.fromValue).toList(growable: false),
      supportedTools: _stringList(json['supported_tools']),
    );
  }

  Map<String, dynamic> toJson() => {
    'protocol_version': liflyDeviceProtocolVersion,
    'capabilities': capabilities
        .map((item) => item.value)
        .toList(growable: false),
    'supported_tools': supportedTools,
  };
}

class DeviceDescriptor {
  final String deviceId;
  final String accountId;
  final String displayName;
  final String platform;
  final String publicKey;
  final DeviceTrustState trustState;
  final DeviceCapabilityReport capabilityReport;
  final bool isDefaultComputeNode;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;
  final int keyVersion;
  final int protocolVersion;

  const DeviceDescriptor({
    required this.deviceId,
    required this.accountId,
    required this.displayName,
    required this.platform,
    required this.publicKey,
    required this.trustState,
    required this.capabilityReport,
    required this.isDefaultComputeNode,
    this.lastSeenAt,
    this.revokedAt,
    this.keyVersion = 1,
    this.protocolVersion = liflyDeviceProtocolVersion,
  });

  factory DeviceDescriptor.fromJson(Map<String, dynamic> json) {
    return DeviceDescriptor(
      deviceId: _requiredString(json, 'device_id'),
      accountId: _requiredString(json, 'account_id'),
      displayName: _requiredString(json, 'display_name'),
      platform: _requiredString(json, 'platform'),
      publicKey: _requiredString(json, 'public_key'),
      trustState: DeviceTrustState.fromValue(
        _requiredString(json, 'trust_state'),
      ),
      capabilityReport: DeviceCapabilityReport.fromJson(
        _requiredMap(json, 'capability_report'),
      ),
      isDefaultComputeNode: json['is_default_compute_node'] as bool? ?? false,
      lastSeenAt: _nullableDateTime(json['last_seen_at']),
      revokedAt: _nullableDateTime(json['revoked_at']),
      keyVersion: _positiveInt(json['key_version'], fallback: 1),
      protocolVersion: _protocolVersion(json['protocol_version']),
    );
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'account_id': accountId,
    'display_name': displayName,
    'platform': platform,
    'public_key': publicKey,
    'trust_state': trustState.value,
    'capability_report': capabilityReport.toJson(),
    'is_default_compute_node': isDefaultComputeNode,
    if (lastSeenAt != null)
      'last_seen_at': lastSeenAt!.toUtc().toIso8601String(),
    if (revokedAt != null) 'revoked_at': revokedAt!.toUtc().toIso8601String(),
    'key_version': keyVersion,
    'protocol_version': protocolVersion,
  };
}

class DeviceEnrollment {
  final String deviceId;
  final String displayName;
  final String platform;
  final String publicKey;
  final DeviceCapabilityReport capabilityReport;
  final bool makeDefaultComputeNode;

  const DeviceEnrollment({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.publicKey,
    this.capabilityReport = const DeviceCapabilityReport(),
    this.makeDefaultComputeNode = false,
  });

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'display_name': displayName,
    'platform': platform,
    'public_key': publicKey,
    'capability_report': capabilityReport.toJson(),
    'make_default_compute_node': makeDefaultComputeNode,
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string for $key');
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) return value.cast<String, dynamic>();
  throw FormatException('Expected object for $key');
}

DateTime? _nullableDateTime(Object? value) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw const FormatException('Expected null or ISO-8601 timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid ISO-8601 timestamp');
  return parsed.toUtc();
}

int _positiveInt(Object? value, {required int fallback}) {
  if (value == null) return fallback;
  if (value is int && value > 0) return value;
  throw const FormatException('Expected positive integer');
}

int _protocolVersion(Object? value) {
  final version = _positiveInt(value, fallback: liflyDeviceProtocolVersion);
  if (version != liflyDeviceProtocolVersion) {
    throw FormatException('Unsupported device protocol version: $version');
  }
  return version;
}

List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('Expected string list');
  return value
      .map((item) {
        if (item is String && item.isNotEmpty) return item;
        throw const FormatException('Expected non-empty string list item');
      })
      .toList(growable: false);
}
