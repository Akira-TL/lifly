class Asset {
  final String id;
  final String userId;
  final String kind;
  final String assetType;
  final String? title;
  final String? filename;
  final String? mimeType;
  final int? sizeBytes;
  final String? sha256;
  final String? storageProvider;
  final String? storageKey;
  final String? externalUrl;
  final String? externalProvider;
  final String visibility;
  final String syncStatus;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Asset({
    required this.id,
    required this.userId,
    required this.kind,
    required this.assetType,
    this.title,
    this.filename,
    this.mimeType,
    this.sizeBytes,
    this.sha256,
    this.storageProvider,
    this.storageKey,
    this.externalUrl,
    this.externalProvider,
    this.visibility = 'private',
    this.syncStatus = 'pending',
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isInternal => kind == 'internal';
  bool get isExternal => kind == 'external';
  bool get isImage => assetType == 'image';
  String get displayName => title ?? filename ?? externalUrl ?? id;

  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      kind: json['kind'] as String,
      assetType: json['asset_type'] as String,
      title: json['title'] as String?,
      filename: json['filename'] as String?,
      mimeType: json['mime_type'] as String?,
      sizeBytes: json['size_bytes'] as int?,
      sha256: json['sha256'] as String?,
      storageProvider: json['storage_provider'] as String?,
      storageKey: json['storage_key'] as String?,
      externalUrl: json['external_url'] as String?,
      externalProvider: json['external_provider'] as String?,
      visibility: json['visibility'] as String,
      syncStatus: json['sync_status'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
