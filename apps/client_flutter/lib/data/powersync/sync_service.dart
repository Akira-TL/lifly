import 'dart:io';

import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/powersync_crud_mapper.dart';
import 'package:client_flutter/data/powersync/local_database_key.dart';
import 'package:client_flutter/data/powersync/local_mutation_committer.dart';
import 'package:client_flutter/data/powersync/powersync_initialization_diagnostics.dart';
import 'package:client_flutter/data/powersync/powersync_schema.dart';
import 'package:client_flutter/data/powersync/sync_push_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:powersync_sqlcipher/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';

class SyncService {
  final SyncPushService pushService;
  final PowerSyncCrudMapper crudMapper;
  final LocalDatabaseKeyProvider databaseKeyProvider;
  final InitializationSingleFlight _initializationFlight =
      InitializationSingleFlight();
  PowerSyncDatabase? _db;
  String? _dbPath;
  PowerSyncInitializationFailure? _lastInitializationFailure;
  SyncPushUploadDiagnostics _uploadDiagnostics =
      const SyncPushUploadDiagnostics.idle();
  LocalMutationCommitter? _localMutationCommitter;

  SyncService({
    ApiClient? api,
    SyncPushService? pushService,
    PowerSyncCrudMapper? crudMapper,
    this.databaseKeyProvider = const LocalDatabaseKeyUnavailable(),
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

      mark('database_key_resolve_start');
      final databaseKey = await databaseKeyProvider.loadOrCreateKey();
      if (databaseKey.isEmpty) {
        throw StateError('Local database encryption key must not be empty');
      }
      mark('database_key_resolve_ok');

      if (!kIsWeb) {
        mark('database_at_rest_migration_start');
        final migrated = await _migratePlaintextDatabaseIfNeeded(
          resolvedPath,
          databaseKey,
        );
        mark(
          'database_at_rest_migration_ok',
          detail: migrated ? 'plaintext_rekeyed' : 'not_required',
        );
      }

      mark('database_construct_start');
      final cipherFactory = PowerSyncSQLCipherOpenFactory(
        path: resolvedPath,
        key: databaseKey,
      );
      final nextDb = PowerSyncDatabase.withFactory(
        cipherFactory,
        schema: liflyPowerSyncSchema,
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

  Future<bool> _migratePlaintextDatabaseIfNeeded(
    String databasePath,
    String databaseKey,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(databaseKey)) {
      throw StateError('Local database encryption key has unsafe encoding');
    }
    final file = File(databasePath);
    final backup = File('$databasePath.plaintext-backup');
    final encryptedTemp = File('$databasePath.sqlcipher-migrating');

    // Recover the only destructive transition in the migration. If an earlier
    // process died after moving the plaintext file aside but before installing
    // the validated encrypted replacement, restore the original first.
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(databasePath);
    }
    if (!await file.exists()) return false;

    final header = await _readDatabaseHeader(file);
    if (!_isPlainSqliteHeader(header)) {
      if (await backup.exists()) {
        await _validateEncryptedDatabase(databasePath, databaseKey);
        await backup.delete();
      }
      return false;
    }
    if (await backup.exists()) {
      throw StateError(
        'Interrupted plaintext database migration needs manual recovery: '
        '${backup.path}',
      );
    }
    if (await encryptedTemp.exists()) {
      await encryptedTemp.delete();
    }

    final plaintextFactory = DefaultSqliteOpenFactory(path: databasePath);
    final raw = plaintextFactory.open(
      const SqliteOpenOptions(primaryConnection: true, readOnly: false),
    );
    try {
      final cipherVersion = raw.select('PRAGMA cipher_version');
      if (cipherVersion.isEmpty) {
        throw StateError(
          'SQLCipher library is unavailable for plaintext migration',
        );
      }
      // PowerSync uses WAL in normal operation. Collapse committed plaintext
      // WAL pages before export so no plaintext sidecar survives migration.
      raw.select('PRAGMA wal_checkpoint(TRUNCATE)');
      raw.select('PRAGMA journal_mode = DELETE');
      final userVersion = _pragmaInt(raw.select('PRAGMA user_version'));
      final applicationId = _pragmaInt(raw.select('PRAGMA application_id'));
      final encryptedPath = _sqlStringLiteral(encryptedTemp.path);
      final keyLiteral = _sqlStringLiteral(databaseKey);
      raw.execute(
        'ATTACH DATABASE $encryptedPath AS lifly_encrypted KEY $keyLiteral',
      );
      try {
        raw.select("SELECT sqlcipher_export('lifly_encrypted')");
        raw.execute('PRAGMA lifly_encrypted.user_version = $userVersion');
        raw.execute('PRAGMA lifly_encrypted.application_id = $applicationId');
      } finally {
        raw.execute('DETACH DATABASE lifly_encrypted');
      }
    } finally {
      raw.dispose();
    }

    await _validateEncryptedDatabase(encryptedTemp.path, databaseKey);
    await file.rename(backup.path);
    try {
      await encryptedTemp.rename(databasePath);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(databasePath);
      }
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('$databasePath$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
    return true;
  }

  Future<List<int>> _readDatabaseHeader(File file) async {
    final handle = await file.open();
    try {
      return await handle.read(16);
    } finally {
      await handle.close();
    }
  }

  Future<void> _validateEncryptedDatabase(String path, String key) async {
    final factory = PowerSyncSQLCipherOpenFactory(path: path, key: key);
    final db = factory.open(
      const SqliteOpenOptions(primaryConnection: true, readOnly: true),
    );
    try {
      db.select('SELECT COUNT(*) FROM sqlite_master');
    } finally {
      db.dispose();
    }
  }

  int _pragmaInt(List<dynamic> rows) {
    if (rows.isEmpty) return 0;
    final row = rows.first;
    if (row is Map) {
      final value = row.values.first;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  String _sqlStringLiteral(String value) => "'${value.replaceAll("'", "''")}'";

  bool _isPlainSqliteHeader(List<int> header) {
    final expected = 'SQLite format 3\u0000'.codeUnits;
    if (header.length < expected.length) return false;
    for (var index = 0; index < expected.length; index += 1) {
      if (header[index] != expected[index]) return false;
    }
    return true;
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

  void setLocalMutationCommitter(LocalMutationCommitter? committer) {
    _localMutationCommitter = committer;
  }

  Future<T> writeLocalTransaction<T>(
    Future<T> Function(SqliteWriteContext transaction) write,
  ) async {
    await ensureInitialized();
    return db.writeTransaction((transaction) async {
      final result = await write(transaction);
      final committer = _localMutationCommitter;
      if (committer != null) {
        await committer.commit(transaction);
      }
      return result;
    });
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
    String? deviceId,
    DateTime? expiresAt,
  }) async {
    if (!isInitialized) return;
    await db.connect(
      connector: _LiflyConnector(
        endpoint: powerSyncEndpoint,
        token: token,
        userId: userId,
        deviceId: deviceId,
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
      deviceId: credentials.deviceId,
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
    _localMutationCommitter = null;
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
  final String? deviceId;
  final DateTime? expiresAt;
  final SyncPushService pushService;
  final PowerSyncCrudMapper crudMapper;
  final void Function(SyncPushUploadDiagnostics diagnostics)
  onUploadDiagnostics;

  _LiflyConnector({
    required this.endpoint,
    required this.token,
    required this.userId,
    required this.deviceId,
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
    final boundDeviceId = deviceId;
    if (boundDeviceId != null && boundDeviceId.isNotEmpty) {
      return boundDeviceId;
    }
    if (entries.isEmpty) return 'lifly-flutter-empty';
    return 'lifly-flutter-${entries.first.clientId}-${entries.last.clientId}';
  }
}
