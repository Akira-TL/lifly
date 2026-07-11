import 'package:client_flutter/data/local_core/local_core_models.dart';

class LocalHomeOverviewBuilder {
  const LocalHomeOverviewBuilder();

  LocalHomeOverview build({
    required List<LocalMemoRecord> memos,
    required List<LocalTaskRecord> tasks,
    required List<LocalLedgerTransactionRecord> transactions,
    required LocalExpenseSummary summary,
    required DateTime now,
    LocalLedgerOverview? ledgerOverview,
    List<LocalLedgerCategorySummary> categoryBreakdown = const [],
    List<LocalLedgerInsight> financeInsights = const [],
    Map<String, LocalTaskReminderStrategy> taskStrategies = const {},
    LocalHomeSyncSummary? syncSummary,
    LocalHomeImportSummary? importSummary,
    LocalHomeSettingsSummary? settingsSummary,
    String userTimezone = 'local',
    String sourceMode = 'local',
  }) {
    final generatedAt = now.toUtc();
    final activeTasks = tasks.where((task) => task.status == 'active').toList();
    final taskTodo = activeTasks
        .where((task) => task.taskStatus == 'todo')
        .toList();
    final overdueTasks = taskTodo
        .where(
          (task) => task.dueAt != null && task.dueAt!.isBefore(generatedAt),
        )
        .toList();
    final todayTasks = taskTodo
        .where(
          (task) =>
              task.dueAt != null && _isSameUtcDay(task.dueAt!, generatedAt),
        )
        .toList();

    final activeTransactions = transactions
        .where((tx) => tx.status == 'active')
        .toList(growable: false);

    return LocalHomeOverview(
      schemaVersion: 'home_overview.v1',
      generatedAt: generatedAt,
      userTimezone: userTimezone,
      sourceMode: sourceMode,
      todayMetrics: LocalHomeTodayMetrics(
        memoTotal: memos.where((memo) => memo.status == 'active').length,
        taskTodo: taskTodo.length,
        taskTotal: activeTasks.length,
        taskOverdue: overdueTasks.length,
        taskDueToday: todayTasks.length,
      ),
      financeOverview: _buildFinanceOverview(
        summary: summary,
        ledgerOverview: ledgerOverview,
        categoryBreakdown: categoryBreakdown,
        financeInsights: financeInsights,
      ),
      attentionItems: _buildAttentionItems(
        overdueTasks,
        todayTasks,
        taskStrategies,
      ),
      dailyTrend: _buildDailyTrend(activeTransactions, generatedAt),
      recentActivity: _buildRecentActivity(
        memos: memos,
        tasks: activeTasks,
        transactions: activeTransactions,
      ),
      syncSummary:
          syncSummary ??
          const LocalHomeSyncSummary(
            status: 'local_only',
            connected: false,
            connecting: false,
            downloading: false,
            uploading: false,
            hasSynced: null,
            lastSyncedAt: null,
            error: null,
            pendingAssetCount: 0,
            failedAssetCount: 0,
          ),
      importSummary: importSummary ?? const LocalHomeImportSummary.idle(),
      settingsSummary:
          settingsSummary ??
          LocalHomeSettingsSummary(
            status: 'ok',
            dataMode: sourceMode,
            localCoreAvailable: true,
            databasePath: null,
            timezone: userTimezone,
          ),
    );
  }

  LocalHomeFinanceOverview _buildFinanceOverview({
    required LocalExpenseSummary summary,
    required LocalLedgerOverview? ledgerOverview,
    required List<LocalLedgerCategorySummary> categoryBreakdown,
    required List<LocalLedgerInsight> financeInsights,
  }) {
    final overview = ledgerOverview;
    final budgetAmount = overview?.budgetAmount;
    final budgetUsed = overview?.budgetUsed;
    return LocalHomeFinanceOverview(
      monthIncome: overview?.monthIncome ?? summary.totalIncome,
      monthExpense: overview?.monthExpense ?? summary.totalExpense,
      transactionCount: overview?.transactionCount ?? summary.count,
      budgetState: overview?.budgetState ?? 'not_configured',
      budgetAmount: budgetAmount,
      budgetUsed: budgetUsed,
      budgetProgress: overview?.budgetProgress,
      budgetRemaining: budgetAmount == null || budgetUsed == null
          ? null
          : budgetAmount - budgetUsed,
      currency: overview?.currency ?? 'CNY',
      categoryBreakdown: categoryBreakdown,
      insights: financeInsights,
    );
  }

  List<LocalHomeAttentionItem> _buildAttentionItems(
    List<LocalTaskRecord> overdueTasks,
    List<LocalTaskRecord> todayTasks,
    Map<String, LocalTaskReminderStrategy> taskStrategies,
  ) {
    final items = <LocalHomeAttentionItem>[];
    for (final task in overdueTasks.take(3)) {
      final strategy = taskStrategies[task.id];
      items.add(
        LocalHomeAttentionItem(
          id: 'overdue_task_${task.id}',
          type: 'task_overdue',
          level: 'critical',
          title: task.title,
          description: strategy?.warningReason ?? '任务已逾期',
          entityType: 'task',
          entityId: task.id,
          occurredAt: task.dueAt,
        ),
      );
    }

    final todayNotOverdue = todayTasks
        .where((task) => !overdueTasks.any((overdue) => overdue.id == task.id))
        .take(3 - items.length);
    for (final task in todayNotOverdue) {
      final strategy = taskStrategies[task.id];
      items.add(
        LocalHomeAttentionItem(
          id: 'today_task_${task.id}',
          type: strategy == null ? 'task_due_today' : 'task_warning_strategy',
          level: _taskAttentionLevel(task, strategy),
          title: task.title,
          description: strategy?.warningReason ?? '今天截止',
          entityType: 'task',
          entityId: task.id,
          occurredAt: task.dueAt ?? strategy?.aiSuggestedRemindAt,
        ),
      );
    }

    return items;
  }

  String _taskAttentionLevel(
    LocalTaskRecord task,
    LocalTaskReminderStrategy? strategy,
  ) {
    if (strategy?.warningLevel == 'critical') return 'critical';
    if (strategy?.warningLevel == 'warning') return 'warning';
    return task.priority == 'high' ? 'warning' : 'normal';
  }

  List<LocalHomeDailyTrendItem> _buildDailyTrend(
    List<LocalLedgerTransactionRecord> transactions,
    DateTime now,
  ) {
    final start = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return List<LocalHomeDailyTrendItem>.generate(7, (index) {
      final day = start.add(Duration(days: index));
      final total = transactions
          .where((tx) => tx.direction == 'expense')
          .where((tx) => _isSameUtcDay(tx.occurredAt, day))
          .fold<double>(0, (sum, tx) => sum + tx.amount);
      return LocalHomeDailyTrendItem(day: day, total: total);
    });
  }

  List<LocalHomeActivityItem> _buildRecentActivity({
    required List<LocalMemoRecord> memos,
    required List<LocalTaskRecord> tasks,
    required List<LocalLedgerTransactionRecord> transactions,
  }) {
    final items = <LocalHomeActivityItem>[
      ...memos
          .where((memo) => memo.status == 'active')
          .map(
            (memo) => LocalHomeActivityItem(
              id: 'memo_${memo.id}',
              entityType: 'memo',
              entityId: memo.id,
              title: memo.title?.trim().isNotEmpty == true
                  ? memo.title!.trim()
                  : '无标题备忘',
              subtitle: memo.contentMarkdown.trim().isEmpty
                  ? null
                  : memo.contentMarkdown.trim(),
              occurredAt: memo.updatedAt,
            ),
          ),
      ...tasks.map(
        (task) => LocalHomeActivityItem(
          id: 'task_${task.id}',
          entityType: 'task',
          entityId: task.id,
          title: task.title,
          subtitle: task.taskStatus == 'done' ? '已完成' : '待处理',
          occurredAt: task.dueAt ?? task.updatedAt,
        ),
      ),
      ...transactions.map(
        (tx) => LocalHomeActivityItem(
          id: 'ledger_transaction_${tx.id}',
          entityType: 'ledger_transaction',
          entityId: tx.id,
          title: tx.merchant?.trim().isNotEmpty == true
              ? tx.merchant!.trim()
              : '账单记录',
          subtitle: tx.note,
          occurredAt: tx.occurredAt,
          amount: tx.amount,
          direction: tx.direction,
        ),
      ),
    ];

    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items.take(10).toList(growable: false);
  }

  bool _isSameUtcDay(DateTime a, DateTime b) {
    final left = a.toUtc();
    final right = b.toUtc();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
