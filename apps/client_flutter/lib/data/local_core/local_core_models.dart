class LocalCoreHealth {
  final String status;
  final String mode;
  final String version;
  final String? detail;
  final DateTime? checkedAt;

  const LocalCoreHealth({
    required this.status,
    required this.mode,
    required this.version,
    this.detail,
    this.checkedAt,
  });

  bool get healthy => status == 'ok';
}

class LocalCoreEntityRef {
  final String type;
  final String id;

  const LocalCoreEntityRef({required this.type, required this.id});
}

class LocalMemoRecord {
  final String id;
  final String type;
  final String? title;
  final String contentMarkdown;
  final List<String> tags;
  final String status;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalMemoRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.contentMarkdown,
    required this.tags,
    required this.status,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });
}

class LocalLedgerTransactionRecord {
  final String id;
  final String direction;
  final double amount;
  final String currency;
  final String? merchant;
  final String? note;
  final DateTime occurredAt;
  final String status;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalLedgerTransactionRecord({
    required this.id,
    required this.direction,
    required this.amount,
    required this.currency,
    required this.merchant,
    required this.note,
    required this.occurredAt,
    required this.status,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });
}

class LocalTaskRecord {
  final String id;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final String priority;
  final String taskStatus;
  final DateTime? completedAt;
  final String status;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalTaskRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.remindAt,
    required this.priority,
    required this.taskStatus,
    required this.completedAt,
    required this.status,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });
}

class LocalAssetRecord {
  final String id;
  final String kind;
  final String assetType;
  final String? title;
  final String? externalUrl;
  final String syncStatus;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalAssetRecord({
    required this.id,
    required this.kind,
    required this.assetType,
    required this.title,
    required this.externalUrl,
    required this.syncStatus,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });
}

class LocalCaptureAction {
  final String type;
  final Map<String, Object?> payload;
  final double confidence;

  const LocalCaptureAction({required this.type, required this.payload, required this.confidence});
}

class LocalCaptureSession {
  final String captureId;
  final List<LocalCaptureAction> actions;
  final bool requiresConfirmation;

  const LocalCaptureSession({
    required this.captureId,
    required this.actions,
    required this.requiresConfirmation,
  });
}

class LocalCaptureCommitResult {
  final bool committed;
  final List<LocalCoreEntityRef> createdEntities;
  final String undoToken;

  const LocalCaptureCommitResult({
    required this.committed,
    required this.createdEntities,
    required this.undoToken,
  });
}

class LocalCaptureUndoResult {
  final int undone;
  final List<LocalCoreEntityRef> failedEntities;

  const LocalCaptureUndoResult({required this.undone, required this.failedEntities});
}

class LocalExpenseSummary {
  final String period;
  final double totalExpense;
  final double totalIncome;
  final int count;

  const LocalExpenseSummary({
    required this.period,
    required this.totalExpense,
    required this.totalIncome,
    required this.count,
  });
}
