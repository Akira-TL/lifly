part of 'home_dashboard_view.dart';

class _TrendPanel extends StatelessWidget {
  final List<HomeDailyTrendItem> items;

  const _TrendPanel({required this.items});

  @override
  Widget build(BuildContext context) {
    return WorkspacePanel(
      title: '近七日支出',
      subtitle: '只保留判断趋势所需的刻度和金额',
      child: items.isEmpty
          ? const WorkspaceEmptyRow(
              icon: Icons.show_chart_outlined,
              message: '暂无可用于趋势判断的流水',
            )
          : _TrendChart(items: items),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<HomeDailyTrendItem> items;

  const _TrendChart({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semanticColors;
    final data = items.length <= 7 ? items : items.sublist(items.length - 7);
    final maximum = data.fold<double>(
      0,
      (current, item) => item.total > current ? item.total : current,
    );
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final item in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      item.total >= 1000
                          ? '${(item.total / 1000).toStringAsFixed(1)}k'
                          : item.total.toStringAsFixed(0),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 18,
                      height: maximum <= 0
                          ? 4
                          : (item.total / maximum * 84)
                                .clamp(4, 84)
                                .toDouble(),
                      decoration: BoxDecoration(
                        color: semantic.info,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _weekdayLabel(item.day),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  final List<HomeActivityItem> items;

  const _RecentActivityPanel({required this.items});

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(8).toList(growable: false);
    return WorkspacePanel(
      key: const Key('home_recent_activity_panel'),
      title: '最近活动',
      subtitle: '备忘、任务和流水按照发生时间混合排列',
      contentPadding: EdgeInsets.zero,
      child: visibleItems.isEmpty
          ? const WorkspaceEmptyRow(
              icon: Icons.history_outlined,
              message: '最近还没有新增或修改的内容',
            )
          : Column(
              children: [
                for (var index = 0; index < visibleItems.length; index++) ...[
                  _ActivityRow(item: visibleItems[index]),
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

class _ActivityRow extends StatelessWidget {
  final HomeActivityItem item;

  const _ActivityRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semanticColors;
    final color = _activityColor(item, semantic);
    final isLedger = item.entityType == 'ledger_transaction';
    final isExpense = item.direction == 'expense';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_activityIcon(item), color: color, size: 17),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle?.trim().isNotEmpty == true
                      ? item.subtitle!.trim()
                      : _activityTypeLabel(item.entityType),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isLedger && item.amount != null)
                Text(
                  '${isExpense ? '-' : '+'}${_currencyFormatter('CNY').format(item.amount)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isExpense ? semantic.critical : semantic.success,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              Text(
                DateFormat('MM/dd HH:mm').format(item.occurredAt.toLocal()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _activityColor(
  HomeActivityItem item,
  LiflySemanticColors semantic,
) {
  return switch (item.entityType) {
    'memo' => semantic.info,
    'task' => semantic.warning,
    'ledger_transaction' => item.direction == 'income'
        ? semantic.success
        : semantic.critical,
    _ => semantic.neutral,
  };
}

IconData _activityIcon(HomeActivityItem item) {
  return switch (item.entityType) {
    'memo' => Icons.note_outlined,
    'task' => Icons.check_circle_outline,
    'ledger_transaction' => item.direction == 'income'
        ? Icons.south_west
        : Icons.north_east,
    _ => Icons.history_outlined,
  };
}

String _activityTypeLabel(String entityType) {
  return switch (entityType) {
    'memo' => '备忘',
    'task' => '任务',
    'ledger_transaction' => '流水',
    _ => '活动',
  };
}

String _weekdayLabel(DateTime day) {
  const labels = ['', '一', '二', '三', '四', '五', '六', '日'];
  return '周${labels[day.toLocal().weekday]}';
}
