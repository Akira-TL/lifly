import 'package:client_flutter/data/local_core/local_core_models.dart';

class LocalTaskCreateInput {
  final String title;
  final String? description;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final String priority;

  const LocalTaskCreateInput({
    required this.title,
    required this.description,
    required this.dueAt,
    required this.remindAt,
    required this.priority,
  });

  factory LocalTaskCreateInput.fromMap(Map<String, Object?> input) {
    final title = _readOptionalString(input, 'title');
    if (title == null) {
      throw ArgumentError('title is required');
    }

    return LocalTaskCreateInput(
      title: title,
      description: _readOptionalString(input, 'description'),
      dueAt: _readOptionalDateTime(input, 'due_at'),
      remindAt: _readOptionalDateTime(input, 'remind_at'),
      priority: _readOptionalString(input, 'priority') ?? 'normal',
    );
  }
}

class LocalTaskListInput {
  final String? taskStatus;
  final String group;
  final int limit;

  const LocalTaskListInput({
    required this.taskStatus,
    required this.group,
    required this.limit,
  });

  factory LocalTaskListInput.fromMap(Map<String, Object?> input) {
    return LocalTaskListInput(
      taskStatus: _readOptionalString(input, 'task_status'),
      group: _readOptionalString(input, 'group') ?? 'all',
      limit: _readPositiveInt(input, 'limit', defaultValue: 20, maxValue: 100),
    );
  }
}

class LocalTaskUpdateInput {
  final String taskId;
  final String? title;
  final String? description;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final String? priority;
  final String? taskStatus;
  final bool hasDescription;
  final bool hasDueAt;
  final bool hasRemindAt;

  const LocalTaskUpdateInput({
    required this.taskId,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.remindAt,
    required this.priority,
    required this.taskStatus,
    required this.hasDescription,
    required this.hasDueAt,
    required this.hasRemindAt,
  });

  factory LocalTaskUpdateInput.fromMap(Map<String, Object?> input) {
    final taskId = _readTaskId(input);
    return LocalTaskUpdateInput(
      taskId: taskId,
      title: _readOptionalString(input, 'title'),
      description: _readOptionalString(input, 'description'),
      dueAt: _readOptionalDateTime(input, 'due_at'),
      remindAt: _readOptionalDateTime(input, 'remind_at'),
      priority: _readOptionalString(input, 'priority'),
      taskStatus: _readOptionalString(input, 'task_status'),
      hasDescription: input.containsKey('description'),
      hasDueAt: input.containsKey('due_at'),
      hasRemindAt: input.containsKey('remind_at'),
    );
  }
}

class LocalTaskCompleteInput {
  final String taskId;

  const LocalTaskCompleteInput({required this.taskId});

  factory LocalTaskCompleteInput.fromMap(Map<String, Object?> input) {
    return LocalTaskCompleteInput(taskId: _readTaskId(input));
  }
}

class LocalTaskDeleteInput {
  final String taskId;
  final String status;

  const LocalTaskDeleteInput({required this.taskId, required this.status});

  factory LocalTaskDeleteInput.fromMap(Map<String, Object?> input) {
    return LocalTaskDeleteInput(
      taskId: _readTaskId(input),
      status: _readOptionalString(input, 'status') ?? 'deleted',
    );
  }
}

class LocalTaskMapper {
  const LocalTaskMapper._();

  static LocalTaskRecord fromRow(Map<String, Object?> row) {
    return LocalTaskRecord(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      description: row['description'] as String?,
      dueAt: _readDateTimeOrNull(row['due_at']),
      remindAt: _readDateTimeOrNull(row['remind_at']),
      priority: row['priority'] as String? ?? 'normal',
      taskStatus: row['task_status'] as String? ?? 'todo',
      completedAt: _readDateTimeOrNull(row['completed_at']),
      status: row['status'] as String? ?? 'active',
      revision: row['revision'] as int? ?? 1,
      createdAt: _readDateTime(row['created_at']),
      updatedAt: _readDateTime(row['updated_at']),
    );
  }

  static Map<String, Object?> snapshot(LocalTaskRecord task) {
    return {
      'id': task.id,
      'title': task.title,
      'description': task.description,
      'due_at': task.dueAt?.toIso8601String(),
      'remind_at': task.remindAt?.toIso8601String(),
      'priority': task.priority,
      'task_status': task.taskStatus,
      'completed_at': task.completedAt?.toIso8601String(),
      'status': task.status,
      'revision': task.revision,
      'created_at': task.createdAt.toIso8601String(),
      'updated_at': task.updatedAt.toIso8601String(),
    };
  }
}

String _readTaskId(Map<String, Object?> input) {
  final taskId =
      _readOptionalString(input, 'task_id') ?? _readOptionalString(input, 'id');
  if (taskId == null) {
    throw ArgumentError('task_id is required');
  }
  return taskId;
}

String? _readOptionalString(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value == null) return null;
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value.trim();
}

DateTime? _readOptionalDateTime(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.parse(value).toUtc();
  }
  return null;
}

DateTime _readDateTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.parse(value).toUtc();
  throw ArgumentError('Expected ISO datetime string, got $value');
}

DateTime? _readDateTimeOrNull(Object? value) {
  if (value == null) return null;
  return _readDateTime(value);
}

int _readPositiveInt(
  Map<String, Object?> input,
  String key, {
  required int defaultValue,
  required int maxValue,
}) {
  final value = input[key];
  if (value is! int || value <= 0) return defaultValue;
  return value > maxValue ? maxValue : value;
}
