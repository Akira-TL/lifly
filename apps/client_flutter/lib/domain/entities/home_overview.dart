class HomeOverview {
  final String schemaVersion;
  final DateTime generatedAt;
  final String userTimezone;
  final String sourceMode;
  final HomeTodayMetrics todayMetrics;
  final HomeFinanceOverview financeOverview;
  final List<HomeAttentionItem> attentionItems;
  final List<HomeDailyTrendItem> dailyTrend;
  final List<HomeActivityItem> recentActivity;
  final String syncStatus;
  final String importStatus;
  final String settingsStatus;

  const HomeOverview({
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

  factory HomeOverview.fromDashboardJson(Map<String, dynamic> json) {
    final generatedAt = DateTime.now().toUtc();
    final todayMetricsJson = _mapValue(json['today_metrics']);
    final financeOverviewJson = _mapValue(json['finance_overview']);
    final syncSummaryJson = _mapValue(json['sync_summary']);
    final importSummaryJson = _mapValue(json['import_summary']);
    final settingsSummaryJson = _mapValue(json['settings_summary']);

    return HomeOverview(
      schemaVersion: json['schema_version'] as String? ?? 'dashboard.v1',
      generatedAt: _dateTime(json['generated_at']) ?? generatedAt,
      userTimezone: json['user_timezone'] as String? ?? 'api',
      sourceMode: json['source_mode'] as String? ?? 'api',
      todayMetrics: HomeTodayMetrics(
        memoTotal: _intValue(
          todayMetricsJson['memo_total'] ?? json['memo_total'],
        ),
        taskTodo: _intValue(todayMetricsJson['task_todo'] ?? json['task_todo']),
        taskTotal: _intValue(
          todayMetricsJson['task_total'] ?? json['task_total'],
        ),
        taskOverdue: _intValue(
          todayMetricsJson['task_overdue'] ?? json['task_overdue'],
        ),
        taskDueToday: _intValue(
          todayMetricsJson['task_due_today'] ?? json['task_due_today'],
        ),
      ),
      financeOverview: HomeFinanceOverview(
        monthIncome: _numValue(
          financeOverviewJson['month_income'] ??
              json['month_income'] ??
              json['monthly_income'],
        ),
        monthExpense: _numValue(
          financeOverviewJson['month_expense'] ??
              json['month_expense'] ??
              json['monthly_expense'],
        ),
        transactionCount: _intValue(
          financeOverviewJson['transaction_count'] ?? json['transaction_count'],
        ),
        budgetState:
            financeOverviewJson['budget_state'] as String? ??
            json['budget_state'] as String? ??
            'not_configured',
        budgetAmount: _nullableNum(financeOverviewJson['budget_amount']),
        budgetUsed: _nullableNum(financeOverviewJson['budget_used']),
        budgetProgress: _nullableNum(financeOverviewJson['budget_progress']),
        budgetRemaining: _nullableNum(financeOverviewJson['budget_remaining']),
        currency: financeOverviewJson['currency'] as String? ?? 'CNY',
        categoryBreakdown: _listOfMaps(
          financeOverviewJson['category_breakdown'],
        ).map(HomeFinanceCategory.fromJson).toList(growable: false),
        insights: _listOfMaps(
          financeOverviewJson['insights'] ?? json['finance_insights'],
        ).map(HomeFinanceInsight.fromJson).toList(growable: false),
      ),
      attentionItems: _listOfMaps(
        json['attention_items'],
      ).map(HomeAttentionItem.fromJson).toList(growable: false),
      dailyTrend: _listOfMaps(
        json['daily_trend'] ?? json['weekly_trend'],
      ).map(HomeDailyTrendItem.fromJson).toList(growable: false),
      recentActivity: _recentActivityFromJson(json),
      syncStatus:
          syncSummaryJson['status'] as String? ??
          json['sync_status'] as String? ??
          'api_available',
      importStatus:
          importSummaryJson['status'] as String? ??
          json['import_status'] as String? ??
          'idle',
      settingsStatus:
          settingsSummaryJson['status'] as String? ??
          json['settings_status'] as String? ??
          'ok',
    );
  }

  static List<HomeActivityItem> _recentActivityFromJson(
    Map<String, dynamic> json,
  ) {
    final explicit = _listOfMaps(json['recent_activity']);
    if (explicit.isNotEmpty) {
      return explicit.map(HomeActivityItem.fromJson).toList(growable: false);
    }

    return _listOfMaps(json['recent_transactions'])
        .map(
          (item) => HomeActivityItem.fromJson({
            'id': item['id'],
            'entity_type': 'ledger_transaction',
            'entity_id': item['id'],
            'title': item['merchant'] ?? item['note'] ?? '账单记录',
            'subtitle': item['note'],
            'occurred_at': item['occurred_at'],
            'amount': item['amount'],
            'direction': item['direction'],
          }),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  static List<Map<String, dynamic>> _listOfMaps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  static double _numValue(Object? value) => value is num ? value.toDouble() : 0;

  static double? _nullableNum(Object? value) => value is num ? value.toDouble() : null;

  static int _intValue(Object? value) => value is num ? value.toInt() : 0;

  static DateTime? _dateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class HomeTodayMetrics {
  final int memoTotal;
  final int taskTodo;
  final int taskTotal;
  final int taskOverdue;
  final int taskDueToday;

  const HomeTodayMetrics({
    required this.memoTotal,
    required this.taskTodo,
    required this.taskTotal,
    required this.taskOverdue,
    required this.taskDueToday,
  });
}

class HomeFinanceOverview {
  final double monthIncome;
  final double monthExpense;
  final int transactionCount;
  final String budgetState;
  final double? budgetAmount;
  final double? budgetUsed;
  final double? budgetProgress;
  final double? budgetRemaining;
  final String currency;
  final List<HomeFinanceCategory> categoryBreakdown;
  final List<HomeFinanceInsight> insights;

  const HomeFinanceOverview({
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

class HomeFinanceCategory {
  final String categoryId;
  final String categoryName;
  final String direction;
  final double amount;
  final double ratio;
  final int transactionCount;
  final String? colorToken;
  final String? iconToken;

  const HomeFinanceCategory({
    required this.categoryId,
    required this.categoryName,
    required this.direction,
    required this.amount,
    required this.ratio,
    required this.transactionCount,
    required this.colorToken,
    required this.iconToken,
  });

  factory HomeFinanceCategory.fromJson(Map<String, dynamic> json) {
    return HomeFinanceCategory(
      categoryId: json['category_id'] as String? ?? 'uncategorized',
      categoryName: json['category_name'] as String? ?? '未分类',
      direction: json['direction'] as String? ?? 'expense',
      amount: HomeOverview._numValue(json['amount']),
      ratio: HomeOverview._numValue(json['ratio'] ?? json['percentage']),
      transactionCount: HomeOverview._intValue(json['transaction_count']),
      colorToken: json['color_token'] as String?,
      iconToken: json['icon_token'] as String?,
    );
  }
}

class HomeFinanceInsight {
  final String id;
  final String type;
  final String level;
  final String title;
  final String description;

  const HomeFinanceInsight({
    required this.id,
    required this.type,
    required this.level,
    required this.title,
    required this.description,
  });

  factory HomeFinanceInsight.fromJson(Map<String, dynamic> json) {
    return HomeFinanceInsight(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      level: json['level'] as String? ?? 'info',
      title: json['title'] as String? ?? '财务提醒',
      description: json['description'] as String? ?? '',
    );
  }
}

class HomeAttentionItem {
  final String id;
  final String type;
  final String level;
  final String title;
  final String? description;
  final String entityType;
  final String entityId;
  final DateTime? occurredAt;

  const HomeAttentionItem({
    required this.id,
    required this.type,
    required this.level,
    required this.title,
    required this.description,
    required this.entityType,
    required this.entityId,
    required this.occurredAt,
  });

  factory HomeAttentionItem.fromJson(Map<String, dynamic> json) {
    return HomeAttentionItem(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      level: json['level'] as String? ?? 'normal',
      title: json['title'] as String? ?? '待关注事项',
      description: json['description'] as String?,
      entityType: json['entity_type'] as String? ?? 'unknown',
      entityId: json['entity_id'] as String? ?? '',
      occurredAt: HomeOverview._dateTime(json['occurred_at']),
    );
  }
}

class HomeDailyTrendItem {
  final DateTime day;
  final double total;

  const HomeDailyTrendItem({required this.day, required this.total});

  factory HomeDailyTrendItem.fromJson(Map<String, dynamic> json) {
    return HomeDailyTrendItem(
      day:
          HomeOverview._dateTime(json['day'] ?? json['date']) ??
          DateTime.now().toUtc(),
      total: HomeOverview._numValue(json['total'] ?? json['amount']),
    );
  }
}

class HomeActivityItem {
  final String id;
  final String entityType;
  final String entityId;
  final String title;
  final String? subtitle;
  final DateTime occurredAt;
  final double? amount;
  final String? direction;

  const HomeActivityItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.subtitle,
    required this.occurredAt,
    this.amount,
    this.direction,
  });

  factory HomeActivityItem.fromJson(Map<String, dynamic> json) {
    final entityId =
        json['entity_id'] as String? ?? json['id'] as String? ?? '';
    return HomeActivityItem(
      id: json['id'] as String? ?? entityId,
      entityType: json['entity_type'] as String? ?? 'unknown',
      entityId: entityId,
      title: json['title'] as String? ?? '最近活动',
      subtitle: json['subtitle'] as String?,
      occurredAt:
          HomeOverview._dateTime(json['occurred_at']) ?? DateTime.now().toUtc(),
      amount: json['amount'] is num ? (json['amount'] as num).toDouble() : null,
      direction: json['direction'] as String?,
    );
  }
}
