import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/task/local_task_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalTaskMapper maps row into LocalTaskRecord', () {
    final createdAt = DateTime.utc(2026, 7, 1, 8);
    final updatedAt = DateTime.utc(2026, 7, 1, 9);
    final completedAt = DateTime.utc(2026, 7, 1, 10);

    final task = LocalTaskMapper.fromRow({
      'id': 'task_1',
      'title': 'Local task',
      'description': 'task body',
      'due_at': '2026-07-02T08:00:00.000Z',
      'remind_at': '2026-07-02T07:30:00.000Z',
      'priority': 'high',
      'task_status': 'done',
      'completed_at': completedAt.toIso8601String(),
      'status': 'active',
      'revision': 2,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    });

    expect(task.id, 'task_1');
    expect(task.priority, 'high');
    expect(task.taskStatus, 'done');
    expect(task.completedAt, completedAt);
    expect(task.revision, 2);
  });

  test('LocalTaskMapper creates serializable snapshots', () {
    final task = LocalTaskRecord(
      id: 'task_1',
      title: 'Snapshot task',
      description: 'snapshot body',
      dueAt: DateTime.utc(2026, 7, 2, 8),
      remindAt: null,
      priority: 'normal',
      taskStatus: 'todo',
      completedAt: null,
      status: 'active',
      revision: 1,
      createdAt: DateTime.utc(2026, 7, 1, 8),
      updatedAt: DateTime.utc(2026, 7, 1, 8),
    );

    final snapshot = LocalTaskMapper.snapshot(task);

    expect(snapshot['id'], 'task_1');
    expect(snapshot['task_status'], 'todo');
    expect(snapshot['due_at'], '2026-07-02T08:00:00.000Z');
    expect(snapshot['created_at'], '2026-07-01T08:00:00.000Z');
  });
}
