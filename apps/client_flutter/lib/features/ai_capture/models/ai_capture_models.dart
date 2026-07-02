class AiCaptureAction {
  const AiCaptureAction({
    required this.type,
    required this.payload,
    required this.confidence,
  });

  final String type;
  final Map<String, dynamic> payload;
  final double confidence;

  factory AiCaptureAction.fromJson(Map<String, dynamic> json) {
    return AiCaptureAction(
      type: json['type'] as String? ?? 'memo_create',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      confidence: (json['confidence'] as num? ?? 0).toDouble(),
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

class AiCaptureParseResult {
  const AiCaptureParseResult({
    required this.captureId,
    required this.actions,
    required this.requiresConfirmation,
  });

  final String captureId;
  final List<AiCaptureAction> actions;
  final bool requiresConfirmation;

  factory AiCaptureParseResult.fromJson(Map<String, dynamic> json) {
    final rawActions = json['actions'] as List? ?? const [];
    return AiCaptureParseResult(
      captureId: json['capture_id'] as String? ?? '',
      actions: rawActions
          .whereType<Map>()
          .map((item) => AiCaptureAction.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      requiresConfirmation: json['requires_confirmation'] as bool? ?? true,
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
  });

  final bool committed;
  final List<AiCaptureEntityRef> createdEntities;
  final List<AiCaptureFailedAction> failedActions;
  final String undoToken;

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
    );
  }
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
