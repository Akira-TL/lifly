class Task {
  final String id;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final String priority;
  String taskStatus;
  final DateTime? completedAt;
  final DateTime createdAt;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.dueAt,
    this.remindAt,
    required this.priority,
    required this.taskStatus,
    this.completedAt,
    required this.createdAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      dueAt: json['due_at'] != null ? DateTime.parse(json['due_at'] as String) : null,
      remindAt: json['remind_at'] != null ? DateTime.parse(json['remind_at'] as String) : null,
      priority: json['priority'] as String? ?? 'normal',
      taskStatus: json['task_status'] as String? ?? 'todo',
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'due_at': dueAt?.toIso8601String(),
    'remind_at': remindAt?.toIso8601String(),
    'priority': priority,
  };

  bool get isDone => taskStatus == 'done';
  bool get isOverdue =>
      !isDone && dueAt != null && dueAt!.isBefore(DateTime.now());
}
