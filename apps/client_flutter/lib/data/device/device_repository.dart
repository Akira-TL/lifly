import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/device/device_contracts.dart';

abstract interface class DeviceTransport {
  Future<Map<String, dynamic>> get(String path);

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? data});

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? data});
}

class ApiClientDeviceTransport implements DeviceTransport {
  final ApiClient _api;

  const ApiClientDeviceTransport(this._api);

  @override
  Future<Map<String, dynamic>> get(String path) => _api.get(path);

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) => _api.post(path, data: data);

  @override
  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? data}) =>
      _api.put(path, data: data);
}

class DeviceRevokeResult {
  final DeviceDescriptor device;
  final int revokedSessions;

  const DeviceRevokeResult({
    required this.device,
    required this.revokedSessions,
  });
}

class DeviceRepository {
  final DeviceTransport _transport;

  const DeviceRepository(this._transport);

  Future<List<DeviceDescriptor>> list() async {
    final response = await _transport.get('/devices');
    final items = response['devices'];
    if (items is! List) {
      throw const FormatException('Expected devices list');
    }
    return items
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Expected device object');
          }
          return DeviceDescriptor.fromJson(item.cast<String, dynamic>());
        })
        .toList(growable: false);
  }

  Future<DeviceDescriptor> rename(String deviceId, String displayName) async {
    final normalized = displayName.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Device display name must not be empty');
    }
    return DeviceDescriptor.fromJson(
      await _transport.put(
        '/devices/$deviceId',
        data: {'display_name': normalized},
      ),
    );
  }

  Future<DeviceDescriptor> heartbeat(
    String deviceId,
    DeviceCapabilityReport report,
  ) async => DeviceDescriptor.fromJson(
    await _transport.post(
      '/devices/$deviceId/heartbeat',
      data: {'capability_report': report.toJson()},
    ),
  );

  Future<DeviceDescriptor> setDefaultComputeNode(String deviceId) async =>
      DeviceDescriptor.fromJson(
        await _transport.put('/devices/$deviceId/default-compute-node'),
      );

  Future<DeviceRevokeResult> revoke(String deviceId) async {
    final response = await _transport.post('/devices/$deviceId/revoke');
    final rawDevice = response['device'];
    final revokedSessions = response['revoked_sessions'];
    if (rawDevice is! Map || revokedSessions is! int || revokedSessions < 0) {
      throw const FormatException('Invalid device revoke response');
    }
    return DeviceRevokeResult(
      device: DeviceDescriptor.fromJson(rawDevice.cast<String, dynamic>()),
      revokedSessions: revokedSessions,
    );
  }
}
