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
    return HomeOverview(
      schemaVersion: json['schema_version'] as String? ?? 'dashboard.v1',
      generatedAt: _dateTime(json['generated_at']) ?? generatedAt,
      userTimezone: json['user_timezone'] as String? ?? 'api',
      sourceMode: json['source_mode'] as String? ?? 'api',
      todayMetrics: HomeTodayMetrics(
        memoTotal: _intValue(json['memo_total']),
        taskTodo: _intValue(json['task_todo']),
        taskTotal: _intValue(json['task_total']),
        taskOverdue: _intValue(json['task_overdue']),
        taskDueToday: _intValue(json['task_due_today']),
      ),
      financeOverview: HomeFinanceOverview(
        monthIncome: _numValue(json['month_income'] ?? json['monthly_income']),
        monthExpense: _numValue(
          json['month_expense'] ?? json['monthly_expense'],
        ),
        transactionCount: _intValue(json['transaction_count']),
        budgetState: json['budget_state'] as String? ?? 'not_configured',
      ),
      attentionItems: _listOfMaps(
        json['attention_items'],
      ).map(HomeAttentionItem.fromJson).toList(growable: false),
      dailyTrend: _listOfMaps(
        json['daily_trend'] ?? json['weekly_trend'],
      ).map(HomeDailyTrendItem.fromJson).toList(growable: false),
      recentActivity: _recentActivityFromJson(json),
      syncStatus: json['sync_status'] as String? ?? 'api_available',
      importStatus: json['import_status'] as String? ?? 'idle',
      settingsStatus: json['settings_status'] as String? ?? 'ok',
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

  static List<Map<String, dynamic>> _listOfMaps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  static double _numValue(Object? value) => value is num ? value.toDouble() : 0;

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

  const HomeFinanceOverview({
    required this.monthIncome,
    required this.monthExpense,
    required this.transactionCount,
    required this.budgetState,
  });
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
