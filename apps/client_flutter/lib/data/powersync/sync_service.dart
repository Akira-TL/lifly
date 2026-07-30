import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/powersync_crud_mapper.dart';
import 'package:client_flutter/data/powersync/powersync_schema.dart';
import 'package:client_flutter/data/powersync/sync_push_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

class SyncService {
  final SyncPushService pushService;
  final PowerSyncCrudMapper crudMapper;
  PowerSyncDatabase? _db;
  String? _dbPath;
  SyncPushUploadDiagnostics _uploadDiagnostics =
      const SyncPushUploadDiagnostics.idle();

  SyncService({
    ApiClient? api,
    SyncPushService? pushService,
    PowerSyncCrudMapper? crudMapper,
  }) : pushService = pushService ?? SyncPushService(api ?? ApiClient()),
       crudMapper = crudMapper ?? const PowerSyncCrudMapper();

  PowerSyncDatabase get db {
    final currentDb = _db;
    if (currentDb == null) {
      throw StateError('PowerSync database has not been initialized.');
    }
    return currentDb;
  }

  String? get dbPath => _dbPath;

  bool get isInitialized => _db != null;

  SyncPushUploadDiagnostics get uploadDiagnostics => _uploadDiagnostics;

  Future<void> initialize({String? dbPath}) async {
    if (isInitialized) return;

    final resolvedPath = dbPath ?? await defaultDatabasePath();
    final nextDb = PowerSyncDatabase(
      schema: liflyPowerSyncSchema,
      path: resolvedPath,
    );

    try {
      await nextDb.initialize();
    } catch (error) {
      if (kIsWeb) {
        throw StateError(
          'Web 本地数据库初始化失败。请确认 sqlite3.wasm、'
          'powersync_db.worker.js 和 powersync_sync.worker.js 已由站点根路径提供。'
          '原始错误：$error',
        );
      }
      rethrow;
    }
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

  Future<void> connect(
    String powerSyncEndpoint,
    String token, {
    String? userId,
    DateTime? expiresAt,
  }) async {
    if (!isInitialized) return;
    await db.connect(
      connector: _LiflyConnector(
        endpoint: powerSyncEndpoint,
        token: token,
        userId: userId,
        expiresAt: expiresAt,
        pushService: pushService,
        crudMapper: crudMapper,
        onUploadDiagnostics: _setUploadDiagnostics,
      ),
    );
  }

  Future<void> connectWithCredentials(
    LiflyPowerSyncCredentials credentials,
  ) async {
    await connect(
      credentials.endpoint,
      credentials.token,
      userId: credentials.userId,
      expiresAt: credentials.expiresAt,
    );
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

  void _setUploadDiagnostics(SyncPushUploadDiagnostics diagnostics) {
    _uploadDiagnostics = diagnostics;
  }
}

class _LiflyConnector extends PowerSyncBackendConnector {
  final String endpoint;
  final String token;
  final String? userId;
  final DateTime? expiresAt;
  final SyncPushService pushService;
  final PowerSyncCrudMapper crudMapper;
  final void Function(SyncPushUploadDiagnostics diagnostics)
  onUploadDiagnostics;

  _LiflyConnector({
    required this.endpoint,
    required this.token,
    required this.userId,
    required this.expiresAt,
    required this.pushService,
    required this.crudMapper,
    required this.onUploadDiagnostics,
  });

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    return PowerSyncCredentials(
      endpoint: endpoint,
      token: token,
      userId: userId,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) return;

    final attemptedAt = DateTime.now().toUtc();
    final request = crudMapper.mapBatch(
      batch.crud,
      clientId: _clientIdForBatch(batch.crud),
      defaultUserId: userId ?? 'local-dev',
      fallbackNow: attemptedAt,
    );

    if (!request.hasChanges) {
      await batch.complete();
      onUploadDiagnostics(
        SyncPushUploadDiagnostics.ignored(
          at: attemptedAt,
          ignoredChanges: request.ignoredCount,
        ),
      );
      return;
    }

    try {
      final result = await pushService.push(request);
      await batch.complete();
      onUploadDiagnostics(
        SyncPushUploadDiagnostics.success(
          at: attemptedAt,
          uploadedChanges: request.changeCount,
          ignoredChanges: request.ignoredCount,
          result: result,
        ),
      );
    } catch (error) {
      onUploadDiagnostics(
        SyncPushUploadDiagnostics.failure(
          at: attemptedAt,
          uploadedChanges: request.changeCount,
          ignoredChanges: request.ignoredCount,
          error: error,
        ),
      );
      rethrow;
    }
  }

  String _clientIdForBatch(List<CrudEntry> entries) {
    if (entries.isEmpty) return 'lifly-flutter-empty';
    return 'lifly-flutter-${entries.first.clientId}-${entries.last.clientId}';
  }
}
