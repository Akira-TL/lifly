class AiCaptureAction {
  const AiCaptureAction({
    required this.type,
    required this.payload,
    required this.confidence,
    this.rawText,
  });

  final String type;
  final Map<String, dynamic> payload;
  final double confidence;
  final String? rawText;

  factory AiCaptureAction.fromJson(Map<String, dynamic> json) {
    return AiCaptureAction(
      type: json['type'] as String? ?? 'memo_create',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      confidence: (json['confidence'] as num? ?? 0).toDouble(),
      rawText: json['raw_text'] as String?,
    );
  }

  String get label {
    return switch (type) {
      'memo_create' => '备忘',
      'task_create' => '任务',
      'expense_create' => '记账',
      'asset_register_external_url' => '链接资产',
      _ => type,
    };
  }

  String get summary {
    final title = payload['title'];
    final content = payload['content_markdown'];
    final merchant = payload['merchant'];
    final amount = payload['amount'];
    final externalUrl = payload['external_url'];

    if (type == 'expense_create') {
      return '${merchant ?? '未知商户'} · ${amount ?? '-'} ${payload['currency'] ?? 'CNY'}';
    }
    if (type == 'task_create') {
      return '${title ?? '未命名任务'}';
    }
    if (type == 'asset_register_external_url') {
      return '${externalUrl ?? '外部链接'}';
    }
    return '${title ?? content ?? '备忘内容'}';
  }
}

class AiCaptureAssetContext {
  const AiCaptureAssetContext({
    required this.assetId,
    this.kind,
    this.assetType,
    this.name,
    this.mimeType,
    this.sizeBytes,
    this.sourceUrl,
    required this.status,
    required this.extractor,
    this.text,
    this.error,
    this.requiredCapability,
  });

  final String assetId;
  final String? kind;
  final String? assetType;
  final String? name;
  final String? mimeType;
  final int? sizeBytes;
  final String? sourceUrl;
  final String status;
  final String extractor;
  final String? text;
  final String? error;
  final String? requiredCapability;

  factory AiCaptureAssetContext.fromJson(Map<String, dynamic> json) {
    return AiCaptureAssetContext(
      assetId: json['asset_id'] as String? ?? '',
      kind: json['kind'] as String?,
      assetType: json['asset_type'] as String?,
      name: json['name'] as String?,
      mimeType: json['mime_type'] as String?,
      sizeBytes: json['size_bytes'] as int?,
      sourceUrl: json['source_url'] as String?,
      status: json['status'] as String? ?? 'metadata_only',
      extractor: json['extractor'] as String? ?? 'metadata',
      text: json['text'] as String?,
      error: json['error'] as String?,
      requiredCapability: json['required_capability'] as String?,
    );
  }

  String get displayName => name ?? sourceUrl ?? assetId;

  bool get isReady => status == 'ready';
}

class AiCaptureTurn {
  const AiCaptureTurn({
    required this.id,
    required this.captureId,
    required this.turnIndex,
    required this.role,
    required this.text,
    required this.assetIds,
    required this.assetContext,
    required this.actions,
    required this.selectedActionIndexes,
    required this.resultEntities,
    required this.undoToken,
    required this.supersedesTurnId,
    required this.turnStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String captureId;
  final int turnIndex;
  final String role;
  final String? text;
  final List<String> assetIds;
  final List<AiCaptureAssetContext> assetContext;
  final List<AiCaptureAction> actions;
  final List<int> selectedActionIndexes;
  final List<AiCaptureEntityRef> resultEntities;
  final String? undoToken;
  final String? supersedesTurnId;
  final String turnStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AiCaptureTurn.fromJson(Map<String, dynamic> json) {
    return AiCaptureTurn(
      id: json['id'] as String? ?? '',
      captureId: json['capture_id'] as String? ?? '',
      turnIndex: json['turn_index'] as int? ?? 0,
      role: json['role'] as String? ?? 'assistant',
      text: json['text'] as String?,
      assetIds: (json['asset_ids'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      assetContext: (json['asset_context'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AiCaptureAssetContext.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      actions: (json['actions'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureAction.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      selectedActionIndexes:
          (json['selected_action_indexes'] as List? ?? const [])
              .whereType<int>()
              .toList(growable: false),
      resultEntities: (json['result_entities'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureEntityRef.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      undoToken: json['undo_token'] as String?,
      supersedesTurnId: json['supersedes_turn_id'] as String?,
      turnStatus: json['turn_status'] as String? ?? 'parsed',
      createdAt: _parseCaptureDateTime(json['created_at']),
      updatedAt: _parseCaptureDateTime(json['updated_at']),
    );
  }

  bool get canCommit => const {'parsed', 'revised', 'failed'}.contains(turnStatus);
  bool get canUndo => undoToken != null && const {'committed', 'partial'}.contains(turnStatus);
  bool get canRevise => !const {'committed', 'partial', 'superseded'}.contains(turnStatus);
}

class AiCaptureSession {
  const AiCaptureSession({
    required this.captureId,
    required this.originalText,
    required this.timezone,
    required this.locale,
    required this.actions,
    required this.requiresConfirmation,
    required this.committed,
    required this.sessionStatus,
    required this.sourceChannel,
    required this.expiresAt,
    required this.committedAt,
    required this.dismissedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.turnCount,
    required this.turns,
  });

  final String captureId;
  final String originalText;
  final String timezone;
  final String locale;
  final List<AiCaptureAction> actions;
  final bool requiresConfirmation;
  final bool committed;
  final String sessionStatus;
  final String sourceChannel;
  final DateTime? expiresAt;
  final DateTime? committedAt;
  final DateTime? dismissedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int turnCount;
  final List<AiCaptureTurn> turns;

  factory AiCaptureSession.fromJson(Map<String, dynamic> json) {
    return AiCaptureSession(
      captureId: json['capture_id'] as String? ?? '',
      originalText: json['original_text'] as String? ?? '',
      timezone: json['timezone'] as String? ?? 'Asia/Shanghai',
      locale: json['locale'] as String? ?? 'zh-CN',
      actions: (json['actions'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureAction.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      requiresConfirmation: json['requires_confirmation'] as bool? ?? true,
      committed: json['committed'] as bool? ?? false,
      sessionStatus: json['session_status'] as String? ?? 'active',
      sourceChannel: json['source_channel'] as String? ?? 'local',
      expiresAt: _parseCaptureDateTime(json['expires_at']),
      committedAt: _parseCaptureDateTime(json['committed_at']),
      dismissedAt: _parseCaptureDateTime(json['dismissed_at']),
      createdAt: _parseCaptureDateTime(json['created_at']),
      updatedAt: _parseCaptureDateTime(json['updated_at']),
      turnCount: json['turn_count'] as int? ??
          (json['turns'] as List? ?? const []).length,
      turns: (json['turns'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureTurn.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
    );
  }

  bool get isDismissed => sessionStatus == 'dismissed';
}

class AiCaptureSessionPage {
  const AiCaptureSessionPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<AiCaptureSession> items;
  final int total;
  final int limit;
  final int offset;

  factory AiCaptureSessionPage.fromJson(Map<String, dynamic> json) {
    return AiCaptureSessionPage(
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureSession.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? 20,
      offset: json['offset'] as int? ?? 0,
    );
  }
}

class AiCaptureParseResult {
  const AiCaptureParseResult({
    required this.captureId,
    required this.actions,
    required this.requiresConfirmation,
    required this.assetContext,
    this.turnId,
  });

  final String captureId;
  final List<AiCaptureAction> actions;
  final bool requiresConfirmation;
  final List<AiCaptureAssetContext> assetContext;
  final String? turnId;

  factory AiCaptureParseResult.fromJson(Map<String, dynamic> json) {
    final rawActions = json['actions'] as List? ?? const [];
    return AiCaptureParseResult(
      captureId: json['capture_id'] as String? ?? '',
      actions: rawActions
          .whereType<Map>()
          .map((item) => AiCaptureAction.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      requiresConfirmation: json['requires_confirmation'] as bool? ?? true,
      assetContext: (json['asset_context'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AiCaptureAssetContext.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      turnId: json['turn_id'] as String?,
    );
  }
}

class AiCaptureFailedAction {
  const AiCaptureFailedAction({
    required this.actionIndex,
    required this.actionType,
    required this.reason,
  });

  final int actionIndex;
  final String? actionType;
  final String reason;

  factory AiCaptureFailedAction.fromJson(Map<String, dynamic> json) {
    return AiCaptureFailedAction(
      actionIndex: json['action_index'] as int? ?? -1,
      actionType: json['action_type'] as String?,
      reason: json['reason'] as String? ?? 'unknown',
    );
  }
}

class AiCaptureEntityRef {
  const AiCaptureEntityRef({required this.type, required this.id});

  final String type;
  final String id;

  factory AiCaptureEntityRef.fromJson(Map<String, dynamic> json) {
    return AiCaptureEntityRef(
      type: json['type'] as String? ?? 'unknown',
      id: json['id'] as String? ?? '',
    );
  }
}

class AiCaptureCommitResult {
  const AiCaptureCommitResult({
    required this.committed,
    required this.createdEntities,
    required this.failedActions,
    required this.undoToken,
    this.captureId,
    this.turnId,
  });

  final bool committed;
  final List<AiCaptureEntityRef> createdEntities;
  final List<AiCaptureFailedAction> failedActions;
  final String undoToken;
  final String? captureId;
  final String? turnId;

  factory AiCaptureCommitResult.fromJson(Map<String, dynamic> json) {
    return AiCaptureCommitResult(
      committed: json['committed'] as bool? ?? false,
      createdEntities: (json['created_entities'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureEntityRef.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      failedActions: (json['failed_actions'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureFailedAction.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      undoToken: json['undo_token'] as String? ?? '',
      captureId: json['capture_id'] as String?,
      turnId: json['turn_id'] as String?,
    );
  }
}

DateTime? _parseCaptureDateTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

class AiCaptureUndoResult {
  const AiCaptureUndoResult({
    required this.undone,
    required this.entities,
    required this.failedEntities,
  });

  final int undone;
  final List<AiCaptureEntityRef> entities;
  final List<AiCaptureEntityRef> failedEntities;

  factory AiCaptureUndoResult.fromJson(Map<String, dynamic> json) {
    return AiCaptureUndoResult(
      undone: json['undone'] as int? ?? 0,
      entities: (json['entities'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureEntityRef.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      failedEntities: (json['failed_entities'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiCaptureEntityRef.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}
