import 'package:sqlite_async/sqlite_async.dart';

Future<void> insertOrUpdatePowerSyncView(
  SqliteWriteContext db, {
  required String table,
  required String id,
  required Map<String, Object?> values,
}) async {
  if (values.isEmpty) {
    throw StateError('Cannot write an empty PowerSync view row for $table/$id');
  }
  _requireSqlIdentifier(table);
  for (final column in values.keys) {
    _requireSqlIdentifier(column);
  }

  final existing = await db.getOptional('SELECT id FROM $table WHERE id = ?', [
    id,
  ]);
  final columns = values.keys.toList(growable: false);
  if (existing == null) {
    final placeholders = List.filled(columns.length + 1, '?').join(', ');
    await db.execute(
      'INSERT INTO $table(id, ${columns.join(', ')}) VALUES ($placeholders)',
      [id, ...columns.map((column) => values[column])],
    );
    return;
  }

  final assignments = columns.map((column) => '$column = ?').join(', ');
  await db.execute('UPDATE $table SET $assignments WHERE id = ?', [
    ...columns.map((column) => values[column]),
    id,
  ]);
}

void _requireSqlIdentifier(String value) {
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
    throw ArgumentError.value(value, 'identifier', 'Unsafe SQL identifier');
  }
}
