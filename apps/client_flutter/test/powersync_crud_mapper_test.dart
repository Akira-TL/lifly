import 'package:client_flutter/data/powersync/powersync_crud_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

void main() {
  const mapper = PowerSyncCrudMapper();
  final fallbackNow = DateTime.utc(2026, 7, 2, 10);

  test('maps memo PUT into sync push upsert payload', () {
    final entry = CrudEntry(1, UpdateType.put, 'memos', 'memo-1', null, {
      'user_id': 'local-dev',
      'type': 'memo',
      'title': 'PowerSync memo',
      'content_markdown': 'local body',
      'tags': '["sync","flutter"]',
      'source': 'flutter',
      'status': 'active',
      'revision': 2,
      'created_at': '2026-07-02T09:00:00Z',
      'updated_at': '2026-07-02T09:30:00Z',
    });

    final request = mapper.mapBatch(
      [entry],
      clientId: 'lifly-flutter-1-1',
      fallbackNow: fallbackNow,
    );

    expect(request.ignoredCount, 0);
    expect(request.changeCount, 1);
    expect(request.toJson(), {
      'client_id': 'lifly-flutter-1-1',
      'changes': [
        {
          'entity_type': 'memo',
          'operation': 'upsert',
          'entity_id': 'memo-1',
          'user_id': 'local-dev',
          'revision': 2,
          'created_at': '2026-07-02T09:00:00.000Z',
          'updated_at': '2026-07-02T09:30:00.000Z',
          'source': 'flutter',
          'data': {
            'type': 'memo',
            'title': 'PowerSync memo',
            'content_markdown': 'local body',
            'tags': ['sync', 'flutter'],
            'source': 'flutter',
            'status': 'active',
          },
        },
      ],
    });
  });

  test('maps soft-deleted task PATCH into delete payload', () {
    final entry = CrudEntry(7, UpdateType.patch, 'tasks', 'task-1', null, {
      'user_id': 'local-dev',
      'title': 'Done task',
      'status': 'deleted',
      'revision': 4,
      'updated_at': '2026-07-02T11:00:00Z',
      'deleted_at': '2026-07-02T11:00:00Z',
    });

    final request = mapper.mapBatch(
      [entry],
      clientId: 'lifly-flutter-7-7',
      fallbackNow: fallbackNow,
    );
    final change = request.changes.single.toJson();

    expect(change['entity_type'], 'task');
    expect(change['operation'], 'delete');
    expect(change['deleted_at'], '2026-07-02T11:00:00.000Z');
    expect((change['data'] as Map<String, Object?>)['status'], 'deleted');
  });

  test('maps ledger budget changes into sync payloads', () {
    final entry = CrudEntry(
      9,
      UpdateType.put,
      'ledger_budgets',
      'budget-1',
      null,
      {
        'user_id': 'local-dev',
        'period_type': 'month',
        'period_key': '2026-07',
        'category_id': 'food',
        'amount': 1200.0,
        'currency': 'CNY',
        'alert_threshold': 0.8,
        'status': 'active',
        'revision': 1,
        'created_at': '2026-07-08T09:00:00Z',
        'updated_at': '2026-07-08T09:00:00Z',
      },
    );

    final request = mapper.mapBatch(
      [entry],
      clientId: 'lifly-flutter-9-9',
      fallbackNow: fallbackNow,
    );
    final change = request.changes.single.toJson();

    expect(change['entity_type'], 'ledger_budget');
    expect(change['operation'], 'upsert');
    expect(change['revision'], 1);
    expect((change['data'] as Map<String, Object?>), containsPair('period_key', '2026-07'));
    expect((change['data'] as Map<String, Object?>), containsPair('category_id', 'food'));
  });

  test('maps reminder delivery state into sync payloads', () {
    final entry = CrudEntry(
      9,
      UpdateType.patch,
      'reminders',
      'reminder-1',
      null,
      {
        'user_id': 'local-dev',
        'target_type': 'task',
        'target_id': 'task-1',
        'remind_at': '2026-07-11T10:00:00Z',
        'channel': 'app',
        'reminder_status': 'failed',
        'attempt_count': 1,
        'max_attempts': 3,
        'next_attempt_at': '2026-07-11T10:01:00Z',
        'last_error': 'permission denied',
        'revision': 2,
        'created_at': '2026-07-11T09:00:00Z',
        'updated_at': '2026-07-11T10:00:00Z',
      },
    );

    final request = mapper.mapBatch(
      [entry],
      clientId: 'lifly-flutter-9-9',
      fallbackNow: fallbackNow,
    );
    final change = request.changes.single.toJson();

    expect(change['entity_type'], 'reminder');
    expect(change['operation'], 'upsert');
    expect(change['revision'], 2);
    expect((change['data'] as Map<String, Object?>), containsPair('reminder_status', 'failed'));
    expect((change['data'] as Map<String, Object?>), containsPair('attempt_count', 1));
  });

  test('maps capture session and turn collections into sync payloads', () {
    final sessionEntry = CrudEntry(
      10,
      UpdateType.patch,
      'mcp_capture_sessions',
      'capture-1',
      null,
      {
        'user_id': 'local-dev',
        'original_text': '连续会话',
        'actions': '[{"type":"memo_create","payload":{"title":"A"},"confidence":0.8}]',
        'committed': 1,
        'session_status': 'active',
        'revision': 3,
        'updated_at': '2026-07-12T10:00:00Z',
      },
    );
    final turnEntry = CrudEntry(
      11,
      UpdateType.patch,
      'mcp_capture_turns',
      'turn-1',
      null,
      {
        'user_id': 'local-dev',
        'capture_id': 'capture-1',
        'turn_index': 3,
        'role': 'assistant',
        'asset_ids': '["asset-1"]',
        'actions': '[{"type":"memo_create","payload":{"title":"B"},"confidence":0.9}]',
        'selected_action_indexes': '[0]',
        'result_entities': '[{"type":"memo","id":"memo-1"}]',
        'undo_token': 'undo-1',
        'turn_status': 'committed',
        'revision': 4,
        'updated_at': '2026-07-12T10:01:00Z',
      },
    );

    final request = mapper.mapBatch(
      [sessionEntry, turnEntry],
      clientId: 'lifly-flutter-10-11',
      fallbackNow: fallbackNow,
    );

    expect(request.changeCount, 2);
    final session = request.changes.first.toJson();
    final turn = request.changes.last.toJson();
    expect(session['entity_type'], 'capture_session');
    expect((session['data'] as Map<String, Object?>)['actions'], isA<List>());
    expect(turn['entity_type'], 'capture_turn');
    expect((turn['data'] as Map<String, Object?>)['asset_ids'], ['asset-1']);
    expect(
      (turn['data'] as Map<String, Object?>)['result_entities'],
      [
        {'type': 'memo', 'id': 'memo-1'},
      ],
    );
  });

  test('ignores unsupported PowerSync CRUD tables', () {
    final auditEntry = CrudEntry(
      8,
      UpdateType.put,
      'audit_logs',
      'audit-1',
      null,
      {'entity_type': 'memo'},
    );

    final request = mapper.mapBatch(
      [auditEntry],
      clientId: 'lifly-flutter-8-8',
      fallbackNow: fallbackNow,
    );

    expect(request.hasChanges, isFalse);
    expect(request.ignoredCount, 1);
    expect(request.toJson(), {'client_id': 'lifly-flutter-8-8', 'changes': []});
  });
}
