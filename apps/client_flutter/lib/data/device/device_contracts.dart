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

  const DeviceDescriptor({
    required this.deviceId,
    required this.accountId,
    required this.displayName,
    required this.platform,
    required this.publicKey,
    required this.trustState,
    required this.capabilityReport,
    required this.isDefaultComputeNode,
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
