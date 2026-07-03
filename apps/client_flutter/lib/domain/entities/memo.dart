import 'package:client_flutter/domain/entities/asset.dart';

class MemoAssetRef {
  final String id;
  final String memoId;
  final String assetId;
  final String refType;
  final String? positionHint;
  final Asset asset;

  const MemoAssetRef({
    required this.id,
    required this.memoId,
    required this.assetId,
    required this.refType,
    required this.asset,
    this.positionHint,
  });

  factory MemoAssetRef.fromJson(Map<String, dynamic> json) {
    return MemoAssetRef(
      id: json['id'] as String,
      memoId: json['memo_id'] as String,
      assetId: json['asset_id'] as String,
      refType: json['ref_type'] as String? ?? 'attachment',
      positionHint: json['position_hint'] as String?,
      asset: Asset.fromJson(json['asset'] as Map<String, dynamic>),
    );
  }
}

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
  final List<MemoAssetRef> assets;

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
    this.assets = const [],
  });

  factory Memo.fromJson(Map<String, dynamic> json) {
    final assetsJson = json['assets'] as List?;
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
      assets: assetsJson == null
          ? const []
          : assetsJson
                .map((item) => MemoAssetRef.fromJson(item as Map<String, dynamic>))
                .toList(growable: false),
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
