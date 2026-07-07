import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';

class HomeOverviewRepository {
  final ApiClient api;
  final LocalCoreBridge? localCore;
  final LiflyDataMode dataMode;

  const HomeOverviewRepository(
    this.api, {
    this.localCore,
    this.dataMode = LiflyDataMode.api,
  });

  bool get _hasLocalCore => localCore != null;

  Future<HomeOverview> load({String period = 'current_month'}) async {
    if (dataMode == LiflyDataMode.local) {
      return _loadLocal(period: period, sourceMode: 'local');
    }

    try {
      return await _loadCloud();
    } catch (cloudError) {
      if (_hasLocalCore) {
        return _loadLocal(period: period, sourceMode: 'fallback');
      }
      throw StateError(
        'Dashboard cloud load failed and local fallback is unavailable: $cloudError',
      );
    }
  }

  Future<HomeOverview> _loadCloud() async {
    final response = await api.get('/home/overview');
    if (response['success'] == true) {
      return HomeOverview.fromDashboardJson(
        response['data'] as Map<String, dynamic>? ?? const {},
      );
    }

    throw StateError(response['error'] as String? ?? 'Dashboard load failed');
  }

  Future<HomeOverview> _loadLocal({
    required String period,
    required String sourceMode,
  }) async {
    final bridge = localCore;
    if (bridge == null) {
      throw StateError('Local Core is unavailable');
    }

    final overview = await bridge.getHomeOverview({
      'period': period,
      'source_mode': sourceMode,
    }, LocalCoreContext.flutterUser());
    return _fromLocal(overview);
  }

  HomeOverview _fromLocal(LocalHomeOverview local) {
    return HomeOverview(
      schemaVersion: local.schemaVersion,
      generatedAt: local.generatedAt,
      userTimezone: local.userTimezone,
      sourceMode: local.sourceMode,
      todayMetrics: _todayMetricsFromLocal(local.todayMetrics),
      financeOverview: _financeOverviewFromLocal(local.financeOverview),
      attentionItems: local.attentionItems
          .map(_attentionItemFromLocal)
          .toList(growable: false),
      dailyTrend: local.dailyTrend
          .map(_dailyTrendItemFromLocal)
          .toList(growable: false),
      recentActivity: local.recentActivity
          .map(_activityItemFromLocal)
          .toList(growable: false),
      syncStatus: local.syncStatus,
      importStatus: local.importStatus,
      settingsStatus: local.settingsStatus,
    );
  }

  HomeTodayMetrics _todayMetricsFromLocal(LocalHomeTodayMetrics local) {
    return HomeTodayMetrics(
      memoTotal: local.memoTotal,
      taskTodo: local.taskTodo,
      taskTotal: local.taskTotal,
      taskOverdue: local.taskOverdue,
      taskDueToday: local.taskDueToday,
    );
  }

  HomeFinanceOverview _financeOverviewFromLocal(
    LocalHomeFinanceOverview local,
  ) {
    return HomeFinanceOverview(
      monthIncome: local.monthIncome,
      monthExpense: local.monthExpense,
      transactionCount: local.transactionCount,
      budgetState: local.budgetState,
    );
  }

  HomeAttentionItem _attentionItemFromLocal(LocalHomeAttentionItem local) {
    return HomeAttentionItem(
      id: local.id,
      type: local.type,
      level: local.level,
      title: local.title,
      description: local.description,
      entityType: local.entityType,
      entityId: local.entityId,
      occurredAt: local.occurredAt,
    );
  }

  HomeDailyTrendItem _dailyTrendItemFromLocal(LocalHomeDailyTrendItem local) {
    return HomeDailyTrendItem(day: local.day, total: local.total);
  }

  HomeActivityItem _activityItemFromLocal(LocalHomeActivityItem local) {
    return HomeActivityItem(
      id: local.id,
      entityType: local.entityType,
      entityId: local.entityId,
      title: local.title,
      subtitle: local.subtitle,
      occurredAt: local.occurredAt,
      amount: local.amount,
      direction: local.direction,
    );
  }
}
