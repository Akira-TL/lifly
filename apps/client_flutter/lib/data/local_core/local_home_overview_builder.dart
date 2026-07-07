import 'package:client_flutter/data/local_core/local_core_models.dart';

class LocalHomeOverviewBuilder {
  const LocalHomeOverviewBuilder();

  LocalHomeOverview build({
    required List<LocalMemoRecord> memos,
    required List<LocalTaskRecord> tasks,
    required List<LocalLedgerTransactionRecord> transactions,
    required LocalExpenseSummary summary,
    required DateTime now,
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
      financeOverview: LocalHomeFinanceOverview(
        monthIncome: summary.totalIncome,
        monthExpense: summary.totalExpense,
        transactionCount: summary.count,
        budgetState: 'not_configured',
      ),
      attentionItems: _buildAttentionItems(overdueTasks, todayTasks),
      dailyTrend: _buildDailyTrend(activeTransactions, generatedAt),
      recentActivity: _buildRecentActivity(
        memos: memos,
        tasks: activeTasks,
        transactions: activeTransactions,
      ),
      syncStatus: 'local_available',
      importStatus: 'idle',
      settingsStatus: 'ok',
    );
  }

  List<LocalHomeAttentionItem> _buildAttentionItems(
    List<LocalTaskRecord> overdueTasks,
    List<LocalTaskRecord> todayTasks,
  ) {
    final items = <LocalHomeAttentionItem>[];
    for (final task in overdueTasks.take(3)) {
      items.add(
        LocalHomeAttentionItem(
          id: 'overdue_task_${task.id}',
          type: 'task_overdue',
          level: 'critical',
          title: task.title,
          description: '任务已逾期',
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
      items.add(
        LocalHomeAttentionItem(
          id: 'today_task_${task.id}',
          type: 'task_due_today',
          level: task.priority == 'high' ? 'warning' : 'normal',
          title: task.title,
          description: '今天截止',
          entityType: 'task',
          entityId: task.id,
          occurredAt: task.dueAt,
        ),
      );
    }

    return items;
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
