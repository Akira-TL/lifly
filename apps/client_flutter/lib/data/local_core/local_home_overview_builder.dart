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
        activeTasks
            .where(
              (task) => task.taskStatus == 'todo' || task.taskStatus == 'doing',
            )
            .toList(growable: false),
        taskStrategies,
        generatedAt,
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
    List<LocalTaskRecord> tasks,
    Map<String, LocalTaskReminderStrategy> taskStrategies,
    DateTime now,
  ) {
    final ranked =
        tasks
            .map((task) {
              final strategy = taskStrategies[task.id];
              final urgencyWindow = _taskUrgencyWindow(task, strategy, now);
              final quadrant = _taskQuadrant(task, urgencyWindow, now);
              return (
                task: task,
                strategy: strategy,
                quadrant: quadrant,
                urgencyWindow: urgencyWindow,
                rank: _quadrantRank(quadrant),
              );
            })
            .toList(growable: false)
          ..sort((left, right) {
            final quadrantOrder = left.rank.compareTo(right.rank);
            if (quadrantOrder != 0) return quadrantOrder;
            final leftDue = left.task.dueAt;
            final rightDue = right.task.dueAt;
            if (leftDue == null && rightDue == null) {
              return right.task.updatedAt.compareTo(left.task.updatedAt);
            }
            if (leftDue == null) return 1;
            if (rightDue == null) return -1;
            return leftDue.compareTo(rightDue);
          });

    return ranked
        .take(8)
        .map((entry) {
          final task = entry.task;
          final strategy = entry.strategy;
          final dueAt = task.dueAt ?? strategy?.aiSuggestedRemindAt;
          final isOverdue = dueAt != null && dueAt.isBefore(now);
          final isDueToday = dueAt != null && _isSameUtcDay(dueAt, now);
          return LocalHomeAttentionItem(
            id: 'focus_task_${task.id}',
            type: isOverdue
                ? 'task_overdue'
                : isDueToday
                ? (strategy == null
                      ? 'task_due_today'
                      : 'task_warning_strategy')
                : 'task_focus',
            level: _quadrantLevel(entry.quadrant),
            quadrant: entry.quadrant,
            urgencyWindowSeconds: entry.urgencyWindow.inSeconds,
            title: task.title,
            description: strategy?.warningReason,
            entityType: 'task',
            entityId: task.id,
            occurredAt: dueAt,
          );
        })
        .toList(growable: false);
  }

  Duration _taskUrgencyWindow(
    LocalTaskRecord task,
    LocalTaskReminderStrategy? strategy,
    DateTime now,
  ) {
    final dueAt = task.dueAt?.toUtc();
    if (dueAt == null) return Duration.zero;

    for (final remindAt in [task.remindAt, strategy?.aiSuggestedRemindAt]) {
      final normalized = remindAt?.toUtc();
      if (normalized != null && normalized.isBefore(dueAt)) {
        return dueAt.difference(normalized);
      }
    }

    final preparationDays = strategy?.preparationWindowDays;
    if (preparationDays != null) {
      return preparationDays > 0
          ? Duration(days: preparationDays)
          : const Duration(hours: 2);
    }

    final remaining = dueAt.difference(now.toUtc());
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
    final text = '${task.title}\n${task.description ?? ''}';
    if (['火车', '高铁', '航班', '飞机', '体检', '预约'].any(text.contains)) {
      return const Duration(hours: 1);
    }
    if (['项目', '总结', '报告', '周报', '提交'].any(text.contains)) {
      return safeRemaining >= const Duration(days: 3)
          ? const Duration(days: 3)
          : safeRemaining >= const Duration(hours: 2)
          ? safeRemaining
          : const Duration(hours: 2);
    }
    if (['回复', '确认', '缴费', '支付', '购买'].any(text.contains)) {
      return const Duration(minutes: 15);
    }
    if (safeRemaining >= const Duration(days: 7)) {
      return const Duration(days: 2);
    }
    if (safeRemaining >= const Duration(days: 2)) {
      return const Duration(hours: 12);
    }
    if (safeRemaining >= const Duration(hours: 6)) {
      return const Duration(hours: 2);
    }
    return const Duration(minutes: 30);
  }

  String _taskQuadrant(
    LocalTaskRecord task,
    Duration urgencyWindow,
    DateTime now,
  ) {
    final important = task.priority == 'high' || task.priority == 'urgent';
    final dueAt = task.dueAt?.toUtc();
    final urgent =
        dueAt != null && !dueAt.isAfter(now.toUtc().add(urgencyWindow));
    if (urgent && important) return 'urgent_important';
    if (urgent) return 'urgent_not_important';
    if (important) return 'not_urgent_important';
    return 'not_urgent_not_important';
  }

  int _quadrantRank(String quadrant) {
    return switch (quadrant) {
      'urgent_important' => 0,
      'urgent_not_important' => 1,
      'not_urgent_important' => 2,
      _ => 3,
    };
  }

  String _quadrantLevel(String quadrant) {
    return switch (quadrant) {
      'urgent_important' => 'critical',
      'urgent_not_important' => 'warning',
      'not_urgent_important' => 'info',
      _ => 'normal',
    };
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
