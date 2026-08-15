import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/powersync_crud_mapper.dart';
import 'package:client_flutter/data/powersync/powersync_initialization_diagnostics.dart';
import 'package:client_flutter/data/powersync/powersync_schema.dart';
import 'package:client_flutter/data/powersync/sync_push_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

typedef LocalMutationFlusher = Future<void> Function();

class SyncService {
  final SyncPushService pushService;
  final PowerSyncCrudMapper crudMapper;
  final InitializationSingleFlight _initializationFlight =
      InitializationSingleFlight();
  PowerSyncDatabase? _db;
  String? _dbPath;
  PowerSyncInitializationFailure? _lastInitializationFailure;
  SyncPushUploadDiagnostics _uploadDiagnostics =
      const SyncPushUploadDiagnostics.idle();
  LocalMutationFlusher? _localMutationFlusher;

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

  PowerSyncInitializationFailure? get lastInitializationFailure =>
      _lastInitializationFailure;

  Future<void> initialize({String? dbPath}) {
    if (isInitialized) return Future<void>.value();

    return _initializationFlight.run(
      () => _initializeOnce(dbPath: dbPath),
      onJoin: () => _logInitializationEvent(
        'join_pending_initialization',
        detail: 'A second caller is awaiting the active database open.',
      ),
    );
  }

  Future<void> _initializeOnce({String? dbPath}) async {
    final occurredAt = DateTime.now().toUtc();
    final diagnosticId =
        'PS-${occurredAt.microsecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    final events = <String>[];
    var stage = 'start';
    var resolvedPath = dbPath ?? '<unresolved>';

    void mark(String nextStage, {Object? detail}) {
      stage = nextStage;
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final message = detail == null
          ? '$timestamp $nextStage'
          : '$timestamp $nextStage | $detail';
      events.add(message);
      _logInitializationEvent(
        nextStage,
        diagnosticId: diagnosticId,
        detail: detail,
      );
    }

    try {
      mark('schema_validate_start');
      liflyPowerSyncSchema.validate();
      mark(
        'schema_validate_ok',
        detail: '${liflyPowerSyncSchema.tables.length} tables',
      );

      mark('database_path_resolve_start');
      resolvedPath = dbPath ?? await defaultDatabasePath();
      mark('database_path_resolve_ok', detail: resolvedPath);

      mark('database_construct_start');
      final nextDb = PowerSyncDatabase(
        schema: liflyPowerSyncSchema,
        path: resolvedPath,
        logger: kIsWeb && kDebugMode ? debugLogger : null,
      );
      mark('database_construct_ok');

      mark('database_initialize_start');
      await nextDb.initialize();
      mark('database_initialize_ok');

      _db = nextDb;
      _dbPath = resolvedPath;
      _lastInitializationFailure = null;
      mark('ready');
    } catch (error, stackTrace) {
      if (!kIsWeb) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      final failure = PowerSyncInitializationFailure(
        diagnosticId: diagnosticId,
        occurredAt: occurredAt,
        stage: stage,
        databasePath: resolvedPath,
        pageUri: Uri.base,
        schemaTableCount: liflyPowerSyncSchema.tables.length,
        cause: error,
        causeStackTrace: stackTrace,
        events: List<String>.unmodifiable(events),
      );
      _lastInitializationFailure = failure;
      debugPrint(failure.report);
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  void _logInitializationEvent(
    String stage, {
    String? diagnosticId,
    Object? detail,
  }) {
    if (!kDebugMode) return;
    final id = diagnosticId ?? 'shared';
    final suffix = detail == null ? '' : ' | $detail';
    debugPrint('[LIFLY_POWERSYNC][$id][$stage]$suffix');
  }

  Future<void> ensureInitialized() => initialize();

  void setLocalMutationFlusher(LocalMutationFlusher? flusher) {
    _localMutationFlusher = flusher;
  }

  Future<void> flushLocalMutations() async {
    final flusher = _localMutationFlusher;
    if (flusher != null) await flusher();
  }

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
    _localMutationFlusher = null;
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
