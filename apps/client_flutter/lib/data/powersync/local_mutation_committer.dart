import 'package:sqlite_async/sqlite_async.dart';

abstract interface class LocalMutationCommitter {
  Future<void> commit(SqliteWriteContext transaction);
}
