class Memo {
  final String id;
  final String type;
  final String? title;
  final String contentMarkdown;
  final List<String>? tags;
  final String? mood;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Memo({
    required this.id,
    required this.type,
    this.title,
    required this.contentMarkdown,
    this.tags,
    this.mood,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Memo.fromJson(Map<String, dynamic> json) {
    return Memo(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String?,
      contentMarkdown: json['content_markdown'] as String? ?? '',
      tags: (json['tags'] as List?)?.cast<String>(),
      mood: json['mood'] as String?,
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'content_markdown': contentMarkdown,
    'tags': tags,
    'mood': mood,
  };

  String get displayTitle => title ?? contentMarkdown.split('\n').first;
}
