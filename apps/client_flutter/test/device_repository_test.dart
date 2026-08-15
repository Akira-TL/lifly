import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/device/device_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _Request {
  final String method;
  final String path;
  final Map<String, dynamic>? data;

  const _Request(this.method, this.path, this.data);
}

class _FakeTransport implements DeviceTransport {
  final requests = <_Request>[];

  @override
  Future<Map<String, dynamic>> get(String path) async {
    requests.add(_Request('GET', path, null));
    return {
      'devices': [
        _deviceJson('phone-1', isDefault: false),
        _deviceJson('desktop-1', isDefault: true),
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    requests.add(_Request('POST', path, data));
    if (path.endsWith('/heartbeat')) {
      return _deviceJson('desktop-1', isDefault: true);
    }
    if (path.endsWith('/revoke')) {
      return {
        'device': _deviceJson(
          'desktop-1',
          isDefault: false,
          trustState: 'revoked',
        ),
        'revoked_sessions': 1,
      };
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    requests.add(_Request('PUT', path, data));
    if (path.endsWith('/default-compute-node')) {
      return _deviceJson('desktop-1', isDefault: true);
    }
    return _deviceJson(
      'desktop-1',
      isDefault: true,
      displayName: 'Workstation',
    );
  }
}

Map<String, dynamic> _deviceJson(
  String deviceId, {
  required bool isDefault,
  String trustState = 'trusted',
  String? displayName,
}) => {
  'device_id': deviceId,
  'account_id': 'account-1',
  'display_name': displayName ?? (deviceId == 'phone-1' ? 'Phone' : 'Desktop'),
  'platform': deviceId == 'phone-1' ? 'android' : 'linux',
  'public_key': 'public-$deviceId',
  'trust_state': trustState,
  'capability_report': {
    'protocol_version': 1,
    'capabilities': deviceId == 'desktop-1'
        ? ['local_ai', 'local_mcp']
        : <String>[],
    'supported_tools': deviceId == 'desktop-1' ? ['memo.create'] : <String>[],
  },
  'is_default_compute_node': isDefault,
  'last_seen_at': '2026-08-15T10:00:00Z',
  'key_version': 1,
  'protocol_version': 1,
};

void main() {
  test(
    'device repository lists, renames and selects default compute node',
    () async {
      final transport = _FakeTransport();
      final repository = DeviceRepository(transport);

      final devices = await repository.list();
      expect(devices, hasLength(2));
      expect(devices.last.capabilityReport.capabilities, [
        DeviceCapability.localAi,
        DeviceCapability.localMcp,
      ]);
      expect(devices.last.lastSeenAt, DateTime.utc(2026, 8, 15, 10));

      final renamed = await repository.rename('desktop-1', 'Workstation');
      expect(renamed.displayName, 'Workstation');
      expect(transport.requests.last.data, {'display_name': 'Workstation'});

      final selected = await repository.setDefaultComputeNode('desktop-1');
      expect(selected.isDefaultComputeNode, isTrue);
      expect(
        transport.requests.last.path,
        '/devices/desktop-1/default-compute-node',
      );
    },
  );

  test(
    'heartbeat reports capabilities and revoke returns session count',
    () async {
      final transport = _FakeTransport();
      final repository = DeviceRepository(transport);
      const report = DeviceCapabilityReport(
        capabilities: [
          DeviceCapability.localAi,
          DeviceCapability.backgroundExecutor,
        ],
        supportedTools: ['task.complete'],
      );

      final heartbeat = await repository.heartbeat('desktop-1', report);
      expect(heartbeat.trustState, DeviceTrustState.trusted);
      expect(
        transport.requests.last.data?['capability_report'],
        report.toJson(),
      );

      final revoked = await repository.revoke('desktop-1');
      expect(revoked.device.trustState, DeviceTrustState.revoked);
      expect(revoked.revokedSessions, 1);
    },
  );
}
