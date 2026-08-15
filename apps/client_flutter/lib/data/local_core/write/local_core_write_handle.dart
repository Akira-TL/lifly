import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:sqlite_async/sqlite_async.dart';

abstract class LocalCoreWriteHandle {
  Future<void> execute(String sql, [List<Object?> parameters = const []]);

  Future<Map<String, Object?>?> getOptional(
    String sql, [
    List<Object?> parameters = const [],
  ]);

  Future<List<Map<String, Object?>>> getAll(
    String sql, [
    List<Object?> parameters = const [],
  ]);
}

class PowerSyncLocalCoreWriteHandle implements LocalCoreWriteHandle {
  final SqliteWriteContext _transaction;

  const PowerSyncLocalCoreWriteHandle(this._transaction);

  @override
  Future<void> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    await _transaction.execute(sql, parameters);
  }

  @override
  Future<Map<String, Object?>?> getOptional(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final row = await _transaction.getOptional(sql, parameters);
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<List<Map<String, Object?>>> getAll(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final rows = await _transaction.getAll(sql, parameters);
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }
}

class LocalCoreWriteExecutor {
  final SyncService syncService;

  const LocalCoreWriteExecutor({required this.syncService});

  Future<T> run<T>(
    Future<T> Function(LocalCoreWriteHandle handle) write,
  ) async {
    try {
      await syncService.ensureInitialized();
      final result = await syncService.db.writeTransaction((transaction) {
        return write(PowerSyncLocalCoreWriteHandle(transaction));
      });
      await syncService.flushLocalMutations();
      return result;
    } catch (error, stackTrace) {
      throw LocalCoreWriteException(
        message: 'Local Core write transaction failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

class LocalCoreWriteException implements Exception {
  final String message;
  final Object cause;
  final StackTrace stackTrace;

  const LocalCoreWriteException({
    required this.message,
    required this.cause,
    required this.stackTrace,
  });

  @override
  String toString() => '$message: $cause';
}
