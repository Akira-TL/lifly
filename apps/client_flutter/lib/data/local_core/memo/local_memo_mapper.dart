import 'dart:convert';

import 'package:client_flutter/data/local_core/local_core_models.dart';

class LocalMemoCreateInput {
  final String type;
  final String? title;
  final String contentMarkdown;
  final List<String> tags;

  const LocalMemoCreateInput({
    required this.type,
    required this.title,
    required this.contentMarkdown,
    required this.tags,
  });

  factory LocalMemoCreateInput.fromMap(Map<String, Object?> input) {
    return LocalMemoCreateInput(
      type: _readOptionalString(input, 'type') ?? 'memo',
      title: _readOptionalString(input, 'title'),
      contentMarkdown: _readOptionalString(input, 'content_markdown') ?? '',
      tags: _readStringList(input, 'tags'),
    );
  }
}

class LocalMemoSearchInput {
  final String query;
  final int limit;

  const LocalMemoSearchInput({required this.query, required this.limit});

  factory LocalMemoSearchInput.fromMap(Map<String, Object?> input) {
    return LocalMemoSearchInput(
      query: (_readOptionalString(input, 'q') ?? '').trim(),
      limit: _readPositiveInt(input, 'limit', defaultValue: 20, maxValue: 100),
    );
  }
}

class LocalMemoUpdateInput {
  final String memoId;
  final String? type;
  final String? title;
  final String? contentMarkdown;
  final List<String>? tags;

  const LocalMemoUpdateInput({
    required this.memoId,
    required this.type,
    required this.title,
    required this.contentMarkdown,
    required this.tags,
  });

  factory LocalMemoUpdateInput.fromMap(Map<String, Object?> input) {
    final memoId =
        _readOptionalString(input, 'memo_id') ??
        _readOptionalString(input, 'id');
    if (memoId == null || memoId.trim().isEmpty) {
      throw ArgumentError('memo_id is required');
    }

    return LocalMemoUpdateInput(
      memoId: memoId.trim(),
      type: _readOptionalString(input, 'type'),
      title: _readOptionalString(input, 'title'),
      contentMarkdown: _readOptionalString(input, 'content_markdown'),
      tags: input.containsKey('tags') ? _readStringList(input, 'tags') : null,
    );
  }
}

class LocalMemoDeleteInput {
  final String memoId;
  final String status;

  const LocalMemoDeleteInput({required this.memoId, required this.status});

  factory LocalMemoDeleteInput.fromMap(Map<String, Object?> input) {
    final memoId =
        _readOptionalString(input, 'memo_id') ??
        _readOptionalString(input, 'id');
    if (memoId == null || memoId.trim().isEmpty) {
      throw ArgumentError('memo_id is required');
    }

    return LocalMemoDeleteInput(
      memoId: memoId.trim(),
      status: _readOptionalString(input, 'status') ?? 'deleted',
    );
  }
}

class LocalMemoMapper {
  const LocalMemoMapper._();

  static LocalMemoRecord fromRow(Map<String, Object?> row) {
    return LocalMemoRecord(
      id: row['id'] as String,
      type: row['type'] as String? ?? 'memo',
      title: row['title'] as String?,
      contentMarkdown: row['content_markdown'] as String? ?? '',
      tags: decodeTags(row['tags'] as String?),
      status: row['status'] as String? ?? 'active',
      revision: row['revision'] as int? ?? 1,
      createdAt: _readDateTime(row['created_at']),
      updatedAt: _readDateTime(row['updated_at']),
    );
  }

  static String encodeTags(List<String> tags) => jsonEncode(tags);

  static List<String> decodeTags(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList(growable: false);
  }

  static Map<String, Object?> snapshot(LocalMemoRecord memo) {
    return {
      'id': memo.id,
      'type': memo.type,
      'title': memo.title,
      'content_markdown': memo.contentMarkdown,
      'tags': memo.tags,
      'status': memo.status,
      'revision': memo.revision,
      'created_at': memo.createdAt.toIso8601String(),
      'updated_at': memo.updatedAt.toIso8601String(),
    };
  }
}

String? _readOptionalString(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value == null) return null;
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value;
}

List<String> _readStringList(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value == null) return const [];
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);
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

DateTime _readDateTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw ArgumentError('Expected ISO datetime string, got $value');
}
