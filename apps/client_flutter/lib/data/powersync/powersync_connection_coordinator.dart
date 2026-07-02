import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/sync_push_service.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

class PowerSyncConnectionDiagnostics {
  final String status;
  final LiflyPowerSyncCredentials? credentials;
  final SyncPushUploadDiagnostics uploadDiagnostics;
  final DateTime? lastAttemptAt;
  final DateTime? connectedAt;
  final DateTime? disconnectedAt;
  final String? error;

  const PowerSyncConnectionDiagnostics({
    required this.status,
    required this.credentials,
    required this.uploadDiagnostics,
    required this.lastAttemptAt,
    required this.connectedAt,
    required this.disconnectedAt,
    required this.error,
  });

  const PowerSyncConnectionDiagnostics.idle()
      : status = 'idle',
        credentials = null,
        uploadDiagnostics = const SyncPushUploadDiagnostics.idle(),
        lastAttemptAt = null,
        connectedAt = null,
        disconnectedAt = null,
        error = null;

  factory PowerSyncConnectionDiagnostics.connected({
    required DateTime at,
    required LiflyPowerSyncCredentials credentials,
    required SyncPushUploadDiagnostics uploadDiagnostics,
  }) {
    return PowerSyncConnectionDiagnostics(
      status: 'connected',
      credentials: credentials,
      uploadDiagnostics: uploadDiagnostics,
      lastAttemptAt: at,
      connectedAt: at,
      disconnectedAt: null,
      error: null,
    );
  }

  factory PowerSyncConnectionDiagnostics.disconnected({
    required DateTime at,
    required PowerSyncConnectionDiagnostics previous,
    required SyncPushUploadDiagnostics uploadDiagnostics,
  }) {
    return PowerSyncConnectionDiagnostics(
      status: 'disconnected',
      credentials: previous.credentials,
      uploadDiagnostics: uploadDiagnostics,
      lastAttemptAt: at,
      connectedAt: previous.connectedAt,
      disconnectedAt: at,
      error: null,
    );
  }

  factory PowerSyncConnectionDiagnostics.failed({
    required DateTime at,
    required Object error,
    required PowerSyncConnectionDiagnostics previous,
    required SyncPushUploadDiagnostics uploadDiagnostics,
  }) {
    return PowerSyncConnectionDiagnostics(
      status: 'failed',
      credentials: previous.credentials,
      uploadDiagnostics: uploadDiagnostics,
      lastAttemptAt: at,
      connectedAt: previous.connectedAt,
      disconnectedAt: previous.disconnectedAt,
      error: error.toString(),
    );
  }

  PowerSyncConnectionDiagnostics refreshed({
    required SyncPushUploadDiagnostics uploadDiagnostics,
  }) {
    return PowerSyncConnectionDiagnostics(
      status: status,
      credentials: credentials,
      uploadDiagnostics: uploadDiagnostics,
      lastAttemptAt: lastAttemptAt,
      connectedAt: connectedAt,
      disconnectedAt: disconnectedAt,
      error: error,
    );
  }

  bool get isConnected => status == 'connected';

  String get statusLabel {
    switch (status) {
      case 'connected':
        return '已连接';
      case 'disconnected':
        return '已断开';
      case 'failed':
        return '失败';
      default:
        return '未连接';
    }
  }
}

class PowerSyncConnectionCoordinator {
  final PowerSyncCredentialsService credentialsService;
  final SyncService syncService;

  PowerSyncConnectionDiagnostics _diagnostics =
      const PowerSyncConnectionDiagnostics.idle();

  PowerSyncConnectionCoordinator({
    required this.credentialsService,
    required this.syncService,
  });

  PowerSyncConnectionDiagnostics get diagnostics => _diagnostics.refreshed(
        uploadDiagnostics: syncService.uploadDiagnostics,
      );

  Future<PowerSyncConnectionDiagnostics> connect() async {
    final attemptedAt = DateTime.now().toUtc();
    try {
      await syncService.ensureInitialized();
      final credentials = await credentialsService.fetchCredentials();
      await syncService.connectWithCredentials(credentials);
      _diagnostics = PowerSyncConnectionDiagnostics.connected(
        at: attemptedAt,
        credentials: credentials,
        uploadDiagnostics: syncService.uploadDiagnostics,
      );
      return _diagnostics;
    } catch (error) {
      _diagnostics = PowerSyncConnectionDiagnostics.failed(
        at: attemptedAt,
        error: error,
        previous: _diagnostics,
        uploadDiagnostics: syncService.uploadDiagnostics,
      );
      return _diagnostics;
    }
  }

  Future<PowerSyncConnectionDiagnostics> disconnect({
    bool clearLocal = false,
  }) async {
    final attemptedAt = DateTime.now().toUtc();
    try {
      await syncService.disconnect(clearLocal: clearLocal);
      _diagnostics = PowerSyncConnectionDiagnostics.disconnected(
        at: attemptedAt,
        previous: _diagnostics,
        uploadDiagnostics: syncService.uploadDiagnostics,
      );
      return _diagnostics;
    } catch (error) {
      _diagnostics = PowerSyncConnectionDiagnostics.failed(
        at: attemptedAt,
        error: error,
        previous: _diagnostics,
        uploadDiagnostics: syncService.uploadDiagnostics,
      );
      return _diagnostics;
    }
  }

  PowerSyncConnectionDiagnostics refreshDiagnostics() {
    _diagnostics = diagnostics;
    return _diagnostics;
  }
}
