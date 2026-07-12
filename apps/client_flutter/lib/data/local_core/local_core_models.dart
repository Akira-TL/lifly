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

class LocalTagMetadata {
  final String id;
  final String name;
  final String kind;
  final String? colorToken;
  final String? iconToken;
  final int? sortOrder;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalTagMetadata({
    required this.id,
    required this.name,
    required this.kind,
    required this.colorToken,
    required this.iconToken,
    required this.sortOrder,
    required this.status,
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

class LocalReminderRecord {
  final String id;
  final String targetType;
  final String targetId;
  final DateTime remindAt;
  final String channel;
  final String status;
  final int attemptCount;
  final int maxAttempts;
  final DateTime? nextAttemptAt;
  final DateTime? lastAttemptAt;
  final DateTime? deliveredAt;
  final DateTime? failedAt;
  final DateTime? cancelledAt;
  final String? lastError;
  final String? externalId;
  final String? dispatchToken;
  final DateTime? leaseUntil;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? title;
  final String? body;

  const LocalReminderRecord({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.remindAt,
    required this.channel,
    required this.status,
    required this.attemptCount,
    required this.maxAttempts,
    required this.nextAttemptAt,
    required this.lastAttemptAt,
    required this.deliveredAt,
    required this.failedAt,
    required this.cancelledAt,
    required this.lastError,
    required this.externalId,
    required this.dispatchToken,
    required this.leaseUntil,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.body,
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
  final String? rawText;

  const LocalCaptureAction({
    required this.type,
    required this.payload,
    required this.confidence,
    this.rawText,
  });
}

class LocalCaptureAssetContext {
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

  const LocalCaptureAssetContext({
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
}

class LocalCaptureTurn {
  final String id;
  final String captureId;
  final int turnIndex;
  final String role;
  final String? text;
  final List<String> assetIds;
  final List<LocalCaptureAssetContext> assetContext;
  final List<LocalCaptureAction> actions;
  final List<int> selectedActionIndexes;
  final List<LocalCoreEntityRef> resultEntities;
  final String? undoToken;
  final String? supersedesTurnId;
  final String turnStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalCaptureTurn({
    required this.id,
    required this.captureId,
    required this.turnIndex,
    required this.role,
    required this.text,
    this.assetIds = const [],
    this.assetContext = const [],
    required this.actions,
    required this.selectedActionIndexes,
    required this.resultEntities,
    this.undoToken,
    this.supersedesTurnId,
    required this.turnStatus,
    required this.createdAt,
    required this.updatedAt,
  });
}

class LocalCaptureSession {
  final String captureId;
  final String originalText;
  final String timezone;
  final String locale;
  final List<LocalCaptureAction> actions;
  final bool requiresConfirmation;
  final bool committed;
  final String sessionStatus;
  final String sourceChannel;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final DateTime? committedAt;
  final DateTime? dismissedAt;
  final List<LocalCaptureTurn> turns;

  const LocalCaptureSession({
    required this.captureId,
    this.originalText = '',
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh-CN',
    required this.actions,
    required this.requiresConfirmation,
    this.committed = false,
    this.sessionStatus = 'active',
    this.sourceChannel = 'local',
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.committedAt,
    this.dismissedAt,
    this.turns = const [],
  });
}

class LocalCaptureCommitResult {
  final bool committed;
  final List<LocalCoreEntityRef> createdEntities;
  final String undoToken;
  final List<LocalCoreEntityRef> failedEntities;

  const LocalCaptureCommitResult({
    required this.committed,
    required this.createdEntities,
    required this.undoToken,
    this.failedEntities = const [],
  });
}

class LocalCaptureUndoResult {
  final int undone;
  final List<LocalCoreEntityRef> entities;
  final List<LocalCoreEntityRef> failedEntities;

  const LocalCaptureUndoResult({
    required this.undone,
    this.entities = const [],
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

class LocalLedgerBudget {
  final String id;
  final String periodType;
  final String periodKey;
  final String? categoryId;
  final double amount;
  final String currency;
  final double? alertThreshold;
  final String status;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalLedgerBudget({
    required this.id,
    required this.periodType,
    required this.periodKey,
    required this.categoryId,
    required this.amount,
    required this.currency,
    required this.alertThreshold,
    required this.status,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
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
  final LocalHomeSyncSummary syncSummary;
  final LocalHomeImportSummary importSummary;
  final LocalHomeSettingsSummary settingsSummary;

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
    required this.syncSummary,
    required this.importSummary,
    required this.settingsSummary,
  });

  String get syncStatus => syncSummary.status;

  String get importStatus => importSummary.status;

  String get settingsStatus => settingsSummary.status;
}

class LocalHomeSyncSummary {
  final String status;
  final bool connected;
  final bool connecting;
  final bool downloading;
  final bool uploading;
  final bool? hasSynced;
  final DateTime? lastSyncedAt;
  final String? error;
  final int pendingAssetCount;
  final int failedAssetCount;

  const LocalHomeSyncSummary({
    required this.status,
    required this.connected,
    required this.connecting,
    required this.downloading,
    required this.uploading,
    required this.hasSynced,
    required this.lastSyncedAt,
    required this.error,
    required this.pendingAssetCount,
    required this.failedAssetCount,
  });
}

class LocalHomeImportSummary {
  final String status;
  final String? latestBatchId;
  final String? sourceProvider;
  final String? filename;
  final int totalRows;
  final int validRows;
  final int duplicateRows;
  final DateTime? createdAt;
  final DateTime? committedAt;
  final DateTime? rolledBackAt;

  const LocalHomeImportSummary({
    required this.status,
    required this.latestBatchId,
    required this.sourceProvider,
    required this.filename,
    required this.totalRows,
    required this.validRows,
    required this.duplicateRows,
    required this.createdAt,
    required this.committedAt,
    required this.rolledBackAt,
  });

  const LocalHomeImportSummary.idle()
      : status = 'idle',
        latestBatchId = null,
        sourceProvider = null,
        filename = null,
        totalRows = 0,
        validRows = 0,
        duplicateRows = 0,
        createdAt = null,
        committedAt = null,
        rolledBackAt = null;
}

class LocalHomeSettingsSummary {
  final String status;
  final String dataMode;
  final bool localCoreAvailable;
  final String? databasePath;
  final String timezone;

  const LocalHomeSettingsSummary({
    required this.status,
    required this.dataMode,
    required this.localCoreAvailable,
    required this.databasePath,
    required this.timezone,
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
  final double? budgetAmount;
  final double? budgetUsed;
  final double? budgetProgress;
  final double? budgetRemaining;
  final String currency;
  final List<LocalLedgerCategorySummary> categoryBreakdown;
  final List<LocalLedgerInsight> insights;

  const LocalHomeFinanceOverview({
    required this.monthIncome,
    required this.monthExpense,
    required this.transactionCount,
    required this.budgetState,
    required this.budgetAmount,
    required this.budgetUsed,
    required this.budgetProgress,
    required this.budgetRemaining,
    required this.currency,
    this.categoryBreakdown = const [],
    this.insights = const [],
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
