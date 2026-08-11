import 'package:client_flutter/app/theme/lifly_semantic_colors.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:client_flutter/features/home/widgets/home_task_focus_visuals.dart';
import 'package:client_flutter/shared/widgets/workspace_panel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

part 'home_dashboard_activity.dart';
part 'home_dashboard_finance.dart';

class HomeDashboardView extends StatelessWidget {
  static const _wideBreakpoint = 1080.0;
  static const _maximumWidth = 1380.0;

  final HomeOverview overview;
  final Future<void> Function() onRefresh;
  final Future<void> Function(HomeAttentionItem item) onCompleteTask;

  const HomeDashboardView({
    super.key,
    required this.overview,
    required this.onRefresh,
    required this.onCompleteTask,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        final horizontalPadding = wide ? 28.0 : 16.0;
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              72,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maximumWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OverviewHeader(overview: overview),
                    const SizedBox(height: 14),
                    _TodayMetricStrip(metrics: overview.todayMetrics),
                    const SizedBox(height: 14),
                    if (wide)
                      _WideDashboard(
                        key: const Key('home_layout_wide'),
                        overview: overview,
                        onCompleteTask: onCompleteTask,
                      )
                    else
                      _CompactDashboard(
                        key: const Key('home_layout_compact'),
                        overview: overview,
                        onCompleteTask: onCompleteTask,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WideDashboard extends StatelessWidget {
  final HomeOverview overview;
  final Future<void> Function(HomeAttentionItem item) onCompleteTask;

  const _WideDashboard({
    super.key,
    required this.overview,
    required this.onCompleteTask,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: Column(
            children: [
              _AttentionPanel(
                items: overview.attentionItems,
                onCompleteTask: onCompleteTask,
              ),
              const SizedBox(height: 14),
              _RecentActivityPanel(items: overview.recentActivity),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              _FinancePanel(finance: overview.financeOverview),
              const SizedBox(height: 14),
              _TrendPanel(items: overview.dailyTrend),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactDashboard extends StatelessWidget {
  final HomeOverview overview;
  final Future<void> Function(HomeAttentionItem item) onCompleteTask;

  const _CompactDashboard({
    super.key,
    required this.overview,
    required this.onCompleteTask,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AttentionPanel(
          items: overview.attentionItems,
          onCompleteTask: onCompleteTask,
        ),
        const SizedBox(height: 14),
        _FinancePanel(finance: overview.financeOverview),
        const SizedBox(height: 14),
        _TrendPanel(items: overview.dailyTrend),
        const SizedBox(height: 14),
        _RecentActivityPanel(items: overview.recentActivity),
      ],
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  final HomeOverview overview;

  const _OverviewHeader({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semanticColors;
    final sourceLocal = overview.sourceMode == 'local';
    final statuses = <_HeaderStatus>[
      _HeaderStatus(
        label: sourceLocal ? '本地计算' : '云端读取',
        detail: sourceLocal ? '断网仍可使用' : '失败时自动回退本地',
        icon: sourceLocal ? Icons.storage_outlined : Icons.cloud_outlined,
        color: sourceLocal ? semantic.success : semantic.info,
      ),
      _syncStatus(overview.syncSummary, semantic),
      _importStatus(overview.importSummary, semantic),
      _settingsStatus(overview.settingsSummary, semantic),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今天需要你关注的内容',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '先处理风险和待办，再查看收支与最近活动。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  DateFormat(
                    'MM/dd HH:mm',
                  ).format(overview.generatedAt.toLocal()),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 22,
              runSpacing: 12,
              children: statuses
                  .map((status) => _HeaderStatusView(status: status))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  _HeaderStatus _syncStatus(
    HomeSyncSummary sync,
    LiflySemanticColors semantic,
  ) {
    if (sync.error?.trim().isNotEmpty == true || sync.failedAssetCount > 0) {
      return _HeaderStatus(
        label: '同步异常',
        detail: sync.failedAssetCount > 0
            ? '${sync.failedAssetCount} 个附件失败'
            : '需要检查连接',
        icon: Icons.sync_problem_outlined,
        color: semantic.critical,
      );
    }
    if (sync.uploading || sync.downloading || sync.connecting) {
      return _HeaderStatus(
        label: '正在同步',
        detail: sync.uploading ? '正在上传变更' : '正在获取更新',
        icon: Icons.sync_outlined,
        color: semantic.info,
      );
    }
    if (sync.connected || sync.hasSynced == true) {
      return _HeaderStatus(
        label: '同步正常',
        detail: sync.lastSyncedAt == null
            ? '连接可用'
            : DateFormat('MM/dd HH:mm').format(sync.lastSyncedAt!.toLocal()),
        icon: Icons.cloud_done_outlined,
        color: semantic.success,
      );
    }
    return _HeaderStatus(
      label: '离线可用',
      detail: '当前显示已有本地数据',
      icon: Icons.cloud_off_outlined,
      color: semantic.warning,
    );
  }

  _HeaderStatus _importStatus(
    HomeImportSummary summary,
    LiflySemanticColors semantic,
  ) {
    final status = summary.status.toLowerCase();
    if (status.contains('fail') || status.contains('error')) {
      return _HeaderStatus(
        label: '导入异常',
        detail: summary.filename ?? '最近批次需要处理',
        icon: Icons.file_download_off_outlined,
        color: semantic.critical,
      );
    }
    if (summary.latestBatchId == null || status == 'idle') {
      return _HeaderStatus(
        label: '暂无导入',
        detail: '微信和支付宝流水可在管理中导入',
        icon: Icons.file_download_outlined,
        color: semantic.neutral,
      );
    }
    final valid = summary.validRows;
    final duplicates = summary.duplicateRows;
    return _HeaderStatus(
      label: '最近导入',
      detail: '$valid 条有效${duplicates > 0 ? ' · $duplicates 条重复' : ''}',
      icon: Icons.file_download_done_outlined,
      color: semantic.success,
    );
  }

  _HeaderStatus _settingsStatus(
    HomeSettingsSummary settings,
    LiflySemanticColors semantic,
  ) {
    final incomplete =
        settings.databaseConfigured == false ||
        settings.powerSyncConfigured == false ||
        settings.objectStorageConfigured == false;
    return _HeaderStatus(
      label: incomplete ? '配置待检查' : '运行环境正常',
      detail: settings.localCoreAvailable
          ? '本地核心可用'
          : '${settings.dataMode.toUpperCase()} 模式',
      icon: incomplete
          ? Icons.settings_suggest_outlined
          : Icons.verified_outlined,
      color: incomplete ? semantic.warning : semantic.success,
    );
  }
}

class _HeaderStatus {
  final String label;
  final String detail;
  final IconData icon;
  final Color color;

  const _HeaderStatus({
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
  });
}

class _HeaderStatusView extends StatelessWidget {
  final _HeaderStatus status;

  const _HeaderStatusView({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 205,
      child: Row(
        children: [
          Icon(status.icon, size: 18, color: status.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  status.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayMetricStrip extends StatelessWidget {
  final HomeTodayMetrics metrics;

  const _TodayMetricStrip({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).semanticColors;
    final definitions = <_MetricDefinition>[
      _MetricDefinition('待处理', metrics.taskTodo, semantic.info),
      _MetricDefinition('任务总数', metrics.taskTotal, semantic.neutral),
      _MetricDefinition('备忘', metrics.memoTotal, semantic.success),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final itemWidth = constraints.maxWidth / columns;
        final theme = Theme.of(context);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            children: definitions
                .map(
                  (metric) => SizedBox(
                    width: itemWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          WorkspaceStatusDot(color: metric.color),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              metric.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            '${metric.value}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

class _MetricDefinition {
  final String label;
  final int value;
  final Color color;

  const _MetricDefinition(this.label, this.value, this.color);
}

class _AttentionPanel extends StatelessWidget {
  final List<HomeAttentionItem> items;
  final Future<void> Function(HomeAttentionItem item) onCompleteTask;

  const _AttentionPanel({
    required this.items,
    required this.onCompleteTask,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(3).toList(growable: false);
    return WorkspacePanel(
      key: const Key('home_attention_panel'),
      title: visibleItems.isEmpty
          ? '今天没有需要优先处理的事项'
          : '先处理这 ${visibleItems.length} 件事',
      subtitle: '颜色表示四象限，时间条表示距离现在的远近',
      trailing: items.length > visibleItems.length
          ? Text(
              '+${items.length - visibleItems.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      contentPadding: EdgeInsets.zero,
      child: visibleItems.isEmpty
          ? const WorkspaceEmptyRow(
              icon: Icons.check_circle_outline,
              message: '当前没有需要优先处理的任务',
            )
          : Column(
              children: [
                for (var index = 0; index < visibleItems.length; index++) ...[
                  _AttentionRow(
                    item: visibleItems[index],
                    onCompleteTask: onCompleteTask,
                  ),
                  if (index != visibleItems.length - 1)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
    );
  }
}

class _AttentionRow extends StatefulWidget {
  final HomeAttentionItem item;
  final Future<void> Function(HomeAttentionItem item) onCompleteTask;

  const _AttentionRow({required this.item, required this.onCompleteTask});

  @override
  State<_AttentionRow> createState() => _AttentionRowState();
}

class _AttentionRowState extends State<_AttentionRow> {
  bool _completing = false;

  Future<void> _complete() async {
    if (_completing || widget.item.entityType != 'task') return;
    setState(() => _completing = true);
    try {
      await widget.onCompleteTask(widget.item);
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final tone = homeTaskQuadrantColor(item.quadrant, theme.semanticColors);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          Semantics(
            label: homeTaskQuadrantLabel(item.quadrant),
            child: Container(
              width: 4,
              height: 50,
              color: tone,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                _AttentionTimeBar(item: item),
              ],
            ),
          ),
          if (item.entityType == 'task') ...[
            const SizedBox(width: 8),
            IconButton(
              key: Key('home_attention_complete_${item.entityId}'),
              tooltip: '完成任务',
              onPressed: _completing ? null : _complete,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              padding: EdgeInsets.zero,
              icon: _completing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radio_button_unchecked, size: 21),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttentionTimeBar extends StatelessWidget {
  final HomeAttentionItem item;

  const _AttentionTimeBar({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueAt = item.occurredAt?.toLocal();
    if (dueAt == null) {
      return Container(
        key: Key('home_attention_time_bar_${item.entityId}'),
        height: 5,
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(99),
        ),
      );
    }
    final distance = dueAt.difference(DateTime.now());
    final tone = homeTaskTimeColor(distance, theme.semanticColors);
    return Row(
      children: [
        Expanded(
          child: Container(
            key: Key('home_attention_time_bar_${item.entityId}'),
            height: 5,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(99),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: homeTaskTimeRatio(distance),
              child: ColoredBox(color: tone),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          homeTaskTimeDistanceLabel(distance),
          style: theme.textTheme.labelSmall?.copyWith(
            color: tone,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

Color _levelColor(String level, LiflySemanticColors semantic) {
  return switch (level.toLowerCase()) {
    'critical' || 'error' || 'danger' => semantic.critical,
    'warning' || 'warn' => semantic.warning,
    'success' || 'ok' => semantic.success,
    'info' => semantic.info,
    _ => semantic.neutral,
  };
}

double _normalizedRatio(double raw) {
  if (!raw.isFinite || raw <= 0) return 0;
  final ratio = raw > 1 ? raw / 100 : raw;
  return ratio.clamp(0, 1).toDouble();
}

NumberFormat _currencyFormatter(String currency) {
  final normalized = currency.trim().toUpperCase();
  return NumberFormat.currency(
    locale: 'zh_CN',
    symbol: normalized == 'CNY' || normalized.isEmpty ? '¥' : '$normalized ',
    decimalDigits: 2,
  );
}
