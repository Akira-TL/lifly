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

class LocalMemoClassification {
  final String id;
  final String memoId;
  final String tag;
  final String source;
  final String status;
  final double? confidence;
  final String? reason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;

  const LocalMemoClassification({
    required this.id,
    required this.memoId,
    required this.tag,
    required this.source,
    required this.status,
    required this.confidence,
    required this.reason,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
  });
}

class LocalTagSummary {
  final String tag;
  final String kind;
  final int count;
  final int confirmedCount;
  final int suggestedCount;
  final String? colorToken;
  final String? iconToken;
  final int? sortOrder;

  const LocalTagSummary({
    required this.tag,
    required this.kind,
    required this.count,
    required this.confirmedCount,
    required this.suggestedCount,
    required this.colorToken,
    required this.iconToken,
    required this.sortOrder,
  });
}

class LocalLedgerTransactionRecord {
  final String id;
  final String direction;
  final double amount;
  final String currency;
  final String? merchant;
  final String? note;
  final String? categoryId;
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
    required this.categoryId,
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

class LocalTaskReminderStrategy {
  final String id;
  final String taskId;
  final String warningLevel;
  final String? warningReason;
  final int? preparationWindowDays;
  final DateTime? aiSuggestedRemindAt;
  final String strategyStatus;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;
  final DateTime? dismissedAt;

  const LocalTaskReminderStrategy({
    required this.id,
    required this.taskId,
    required this.warningLevel,
    required this.warningReason,
    required this.preparationWindowDays,
    required this.aiSuggestedRemindAt,
    required this.strategyStatus,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
    required this.dismissedAt,
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

  const LocalCaptureAction({
    required this.type,
    required this.payload,
    required this.confidence,
  });
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

  const LocalCaptureUndoResult({
    required this.undone,
    required this.failedEntities,
  });
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

class LocalLedgerOverview {
  final String schemaVersion;
  final DateTime generatedAt;
  final String period;
  final String sourceMode;
  final double monthIncome;
  final double monthExpense;
  final int transactionCount;
  final String budgetState;
  final double? budgetAmount;
  final double? budgetUsed;
  final double? budgetProgress;
  final String currency;

  const LocalLedgerOverview({
    required this.schemaVersion,
    required this.generatedAt,
    required this.period,
    required this.sourceMode,
    required this.monthIncome,
    required this.monthExpense,
    required this.transactionCount,
    required this.budgetState,
    required this.budgetAmount,
    required this.budgetUsed,
    required this.budgetProgress,
    required this.currency,
  });
}

class LocalLedgerCategorySummary {
  final String categoryId;
  final String categoryName;
  final String direction;
  final double amount;
  final double ratio;
  final int transactionCount;

  const LocalLedgerCategorySummary({
    required this.categoryId,
    required this.categoryName,
    required this.direction,
    required this.amount,
    required this.ratio,
    required this.transactionCount,
  });
}

class LocalLedgerInsight {
  final String id;
  final String type;
  final String level;
  final String title;
  final String description;

  const LocalLedgerInsight({
    required this.id,
    required this.type,
    required this.level,
    required this.title,
    required this.description,
  });
}

class LocalHomeOverview {
  final String schemaVersion;
  final DateTime generatedAt;
  final String userTimezone;
  final String sourceMode;
  final LocalHomeTodayMetrics todayMetrics;
  final LocalHomeFinanceOverview financeOverview;
  final List<LocalHomeAttentionItem> attentionItems;
  final List<LocalHomeDailyTrendItem> dailyTrend;
  final List<LocalHomeActivityItem> recentActivity;
  final String syncStatus;
  final String importStatus;
  final String settingsStatus;

  const LocalHomeOverview({
    required this.schemaVersion,
    required this.generatedAt,
    required this.userTimezone,
    required this.sourceMode,
    required this.todayMetrics,
    required this.financeOverview,
    required this.attentionItems,
    required this.dailyTrend,
    required this.recentActivity,
    required this.syncStatus,
    required this.importStatus,
    required this.settingsStatus,
  });
}

class LocalHomeTodayMetrics {
  final int memoTotal;
  final int taskTodo;
  final int taskTotal;
  final int taskOverdue;
  final int taskDueToday;

  const LocalHomeTodayMetrics({
    required this.memoTotal,
    required this.taskTodo,
    required this.taskTotal,
    required this.taskOverdue,
    required this.taskDueToday,
  });
}

class LocalHomeFinanceOverview {
  final double monthIncome;
  final double monthExpense;
  final int transactionCount;
  final String budgetState;

  const LocalHomeFinanceOverview({
    required this.monthIncome,
    required this.monthExpense,
    required this.transactionCount,
    required this.budgetState,
  });
}

class LocalHomeAttentionItem {
  final String id;
  final String type;
  final String level;
  final String title;
  final String? description;
  final String entityType;
  final String entityId;
  final DateTime? occurredAt;

  const LocalHomeAttentionItem({
    required this.id,
    required this.type,
    required this.level,
    required this.title,
    required this.description,
    required this.entityType,
    required this.entityId,
    required this.occurredAt,
  });
}

class LocalHomeDailyTrendItem {
  final DateTime day;
  final double total;

  const LocalHomeDailyTrendItem({required this.day, required this.total});
}

class LocalHomeActivityItem {
  final String id;
  final String entityType;
  final String entityId;
  final String title;
  final String? subtitle;
  final DateTime occurredAt;
  final double? amount;
  final String? direction;

  const LocalHomeActivityItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.subtitle,
    required this.occurredAt,
    this.amount,
    this.direction,
  });
}
