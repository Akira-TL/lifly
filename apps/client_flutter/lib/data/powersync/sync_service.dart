import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/powersync_schema.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

class SyncService {
  PowerSyncDatabase? _db;
  String? _dbPath;

  PowerSyncDatabase get db {
    final currentDb = _db;
    if (currentDb == null) {
      throw StateError('PowerSync database has not been initialized.');
    }
    return currentDb;
  }

  String? get dbPath => _dbPath;

  bool get isInitialized => _db != null;

  Future<void> initialize({String? dbPath}) async {
    if (isInitialized) return;

    final resolvedPath = dbPath ?? await defaultDatabasePath();
    final nextDb = PowerSyncDatabase(
      schema: liflyPowerSyncSchema,
      path: resolvedPath,
    );

    await nextDb.initialize();
    _db = nextDb;
    _dbPath = resolvedPath;
  }

  Future<void> ensureInitialized() => initialize();

  Future<String> defaultDatabasePath() async {
    if (kIsWeb) {
      return 'lifly-local-core.db';
    }

    final directory = await getApplicationSupportDirectory();
    return path.join(directory.path, 'lifly-local-core.db');
  }

  Future<void> connect(String powerSyncEndpoint, String token) async {
    if (!isInitialized) return;
    await db.connect(connector: _LiflyConnector(powerSyncEndpoint, token));
  }

  Future<void> connectWithCredentials(
    LiflyPowerSyncCredentials credentials,
  ) async {
    await connect(credentials.endpoint, credentials.token);
  }

  Future<void> disconnect({bool clearLocal = false}) async {
    if (!isInitialized) return;

    if (clearLocal) {
      await db.disconnectAndClear();
      return;
    }

    await db.disconnect();
  }

  void dispose() {
    if (!isInitialized) return;
    db.close();
    _db = null;
    _dbPath = null;
  }
}

class _LiflyConnector extends PowerSyncBackendConnector {
  final String endpoint;
  final String token;

  _LiflyConnector(this.endpoint, this.token);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    return PowerSyncCredentials(endpoint: endpoint, token: token);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) return;
    await batch.complete();
  }
}
