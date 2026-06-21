import 'package:powersync/powersync.dart';

class SyncService {
  late final PowerSyncDatabase db;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize(String dbPath) async {
    db = PowerSyncDatabase(
      schema: _lifilySchema,
      path: dbPath,
    );

    await db.initialize();
    _initialized = true;
  }

  Future<void> connect(String powerSyncEndpoint, String token) async {
    if (!_initialized) return;
    await db.connect(
      connector: _LifilyConnector(powerSyncEndpoint, token),
    );
  }

  Future<void> disconnect() async {
    if (_initialized) {
      await db.disconnectAndClear();
    }
  }

  void dispose() {
    if (_initialized) db.close();
  }
}

class _LifilyConnector extends PowerSyncBackendConnector {
  final String endpoint;
  final String token;

  _LifilyConnector(this.endpoint, this.token);

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

const _lifilySchema = Schema([
  Table('memos', [
    Column.text('id'),
    Column.text('user_id'),
    Column.text('type'),
    Column.text('title'),
    Column.text('content_markdown'),
    Column.text('mood'),
    Column.text('status'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ]),
  Table('tasks', [
    Column.text('id'),
    Column.text('user_id'),
    Column.text('title'),
    Column.text('description'),
    Column.text('due_at'),
    Column.text('remind_at'),
    Column.text('priority'),
    Column.text('task_status'),
    Column.text('status'),
    Column.text('created_at'),
    Column.text('updated_at'),
    Column.text('completed_at'),
  ]),
  Table('ledger_transactions', [
    Column.text('id'),
    Column.text('user_id'),
    Column.text('direction'),
    Column.real('amount'),
    Column.text('currency'),
    Column.text('merchant'),
    Column.text('note'),
    Column.text('occurred_at'),
    Column.text('status'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ]),
]);
