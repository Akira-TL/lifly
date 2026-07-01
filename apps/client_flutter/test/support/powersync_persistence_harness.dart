import 'dart:io';

import 'package:client_flutter/data/powersync/sync_service.dart';

class PowerSyncPersistenceHarness {
  final Directory tempDir;
  final String dbPath;

  const PowerSyncPersistenceHarness._({
    required this.tempDir,
    required this.dbPath,
  });

  static Future<PowerSyncPersistenceHarness> create(String prefix) async {
    final tempDir = await Directory.systemTemp.createTemp(prefix);
    return PowerSyncPersistenceHarness._(
      tempDir: tempDir,
      dbPath: '${tempDir.path}/lifly-persistence-test.db',
    );
  }

  Future<SyncService?> openService() async {
    final service = SyncService();
    try {
      await service.initialize(dbPath: dbPath);
      return service;
    } catch (_) {
      service.dispose();
      return null;
    }
  }

  Future<void> dispose() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
