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
      syncSummary: _syncSummaryFromLocal(local.syncSummary),
      importSummary: _importSummaryFromLocal(local.importSummary),
      settingsSummary: _settingsSummaryFromLocal(local.settingsSummary),
    );
  }

  HomeSyncSummary _syncSummaryFromLocal(LocalHomeSyncSummary local) {
    return HomeSyncSummary(
      status: local.status,
      mode: 'local',
      connected: local.connected,
      connecting: local.connecting,
      downloading: local.downloading,
      uploading: local.uploading,
      hasSynced: local.hasSynced,
      lastSyncedAt: local.lastSyncedAt,
      error: local.error,
      powerSyncConfigured: null,
      pendingAssetCount: local.pendingAssetCount,
      failedAssetCount: local.failedAssetCount,
      syncedAssetCount: 0,
    );
  }

  HomeImportSummary _importSummaryFromLocal(LocalHomeImportSummary local) {
    return HomeImportSummary(
      status: local.status,
      latestBatchId: local.latestBatchId,
      sourceProvider: local.sourceProvider,
      filename: local.filename,
      totalRows: local.totalRows,
      validRows: local.validRows,
      duplicateRows: local.duplicateRows,
      createdAt: local.createdAt,
      committedAt: local.committedAt,
      rolledBackAt: local.rolledBackAt,
    );
  }

  HomeSettingsSummary _settingsSummaryFromLocal(
    LocalHomeSettingsSummary local,
  ) {
    return HomeSettingsSummary(
      status: local.status,
      mode: 'local',
      dataMode: local.dataMode,
      localCoreAvailable: local.localCoreAvailable,
      databasePath: local.databasePath,
      timezone: local.timezone,
      databaseConfigured: null,
      powerSyncConfigured: null,
      objectStorageConfigured: null,
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
      budgetAmount: local.budgetAmount,
      budgetUsed: local.budgetUsed,
      budgetProgress: local.budgetProgress,
      budgetRemaining: local.budgetRemaining,
      currency: local.currency,
      categoryBreakdown: local.categoryBreakdown
          .map(_financeCategoryFromLocal)
          .toList(growable: false),
      insights: local.insights
          .map(_financeInsightFromLocal)
          .toList(growable: false),
    );
  }

  HomeFinanceCategory _financeCategoryFromLocal(
    LocalLedgerCategorySummary local,
  ) {
    return HomeFinanceCategory(
      categoryId: local.categoryId,
      categoryName: local.categoryName,
      direction: local.direction,
      amount: local.amount,
      ratio: local.ratio,
      transactionCount: local.transactionCount,
      colorToken: null,
      iconToken: null,
    );
  }

  HomeFinanceInsight _financeInsightFromLocal(LocalLedgerInsight local) {
    return HomeFinanceInsight(
      id: local.id,
      type: local.type,
      level: local.level,
      title: local.title,
      description: local.description,
    );
  }

  HomeAttentionItem _attentionItemFromLocal(LocalHomeAttentionItem local) {
    return HomeAttentionItem(
      id: local.id,
      type: local.type,
      level: local.level,
      quadrant: local.quadrant,
      urgencyWindowSeconds: local.urgencyWindowSeconds,
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
