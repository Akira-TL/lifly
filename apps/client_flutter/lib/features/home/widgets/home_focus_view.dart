import 'package:client_flutter/app/theme/lifly_semantic_colors.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

part 'home_focus_agenda.dart';
part 'home_focus_finance.dart';

class HomeFocusView extends StatelessWidget {
  static const _agendaBreakpoint = 860.0;

  final HomeOverview overview;
  final Future<void> Function() onRefresh;

  const HomeFocusView({
    super.key,
    required this.overview,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _agendaBreakpoint) {
          final agendaWidth = (constraints.maxWidth * 0.3)
              .clamp(260.0, 330.0)
              .toDouble();
          return Row(
            key: const Key('home_focus_layout_wide'),
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: onRefresh,
                  child: ListView(
                    key: const PageStorageKey('home-focus-primary'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(30, 27, 30, 38),
                    children: [
                      _FocusQueueSection(items: overview.attentionItems),
                      const SizedBox(height: 32),
                      _FocusSecondarySections(overview: overview),
                    ],
                  ),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              SizedBox(
                width: agendaWidth,
                child: HomeFocusAgenda(overview: overview),
              ),
            ],
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            key: const Key('home_focus_layout_compact'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 48),
            children: [
              _FocusQueueSection(items: overview.attentionItems),
              const SizedBox(height: 28),
              _FocusSecondarySections(overview: overview),
              const SizedBox(height: 30),
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              HomeFocusAgenda(overview: overview, embedded: true),
            ],
          ),
        );
      },
    );
  }
}

class _FocusQueueSection extends StatelessWidget {
  final List<HomeAttentionItem> items;

  const _FocusQueueSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(4).toList(growable: false);
    return Column(
      key: const Key('home_focus_queue'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusSectionHeader(
          title: visibleItems.isEmpty
              ? '今天没有需要优先处理的事项'
              : '先处理这 ${visibleItems.length} 件事',
          subtitle: '首页只放今天需要判断或执行的内容',
          actionLabel: items.length > visibleItems.length
              ? '还有 ${items.length - visibleItems.length} 项'
              : null,
        ),
        if (visibleItems.isEmpty)
          const _FocusEmptyLine(message: '当前没有逾期、今天截止或需要确认的事项')
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            child: Column(
              children: [
                for (var index = 0; index < visibleItems.length; index++) ...[
                  _FocusQueueRow(item: visibleItems[index]),
                  if (index != visibleItems.length - 1)
                    Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FocusQueueRow extends StatelessWidget {
  final HomeAttentionItem item;

  const _FocusQueueRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _focusLevelColor(item.level, theme.semanticColors);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 63),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 13,
            bottom: 13,
            child: Container(width: 3, color: tone),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 13, 10),
            child: Row(
              children: [
                Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.description?.trim().isNotEmpty == true
                            ? item.description!.trim()
                            : _focusEntityLabel(item.entityType),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _focusQueueSideTitle(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _focusTypeLabel(item.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                    ],
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

class _FocusSecondarySections extends StatelessWidget {
  final HomeOverview overview;

  const _FocusSecondarySections({required this.overview});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;
        if (!twoColumns) {
          return Column(
            children: [
              HomeFocusFinanceSection(finance: overview.financeOverview),
              const SizedBox(height: 28),
              _RecentMemoSection(items: overview.recentActivity),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 105,
              child: HomeFocusFinanceSection(finance: overview.financeOverview),
            ),
            const SizedBox(width: 28),
            Expanded(
              flex: 95,
              child: _RecentMemoSection(items: overview.recentActivity),
            ),
          ],
        );
      },
    );
  }
}

class _RecentMemoSection extends StatelessWidget {
  final List<HomeActivityItem> items;

  const _RecentMemoSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final memos = items
        .where((item) => item.entityType == 'memo')
        .take(3)
        .toList(growable: false);
    return Column(
      key: const Key('home_focus_recent_memos'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FocusSectionHeader(title: '最近备忘', subtitle: '继续上次未完成的思路'),
        if (memos.isEmpty)
          const _FocusEmptyLine(message: '最近活动里还没有备忘')
        else
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            child: Column(
              children: [
                for (var index = 0; index < memos.length; index++) ...[
                  _RecentMemoRow(item: memos[index]),
                  if (index != memos.length - 1)
                    Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentMemoRow extends StatelessWidget {
  final HomeActivityItem item;

  const _RecentMemoRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 45),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle?.trim().isNotEmpty == true
                        ? item.subtitle!.trim()
                        : '备忘',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _focusRelativeTime(item.occurredAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;

  const _FocusSectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null)
            Text(
              actionLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}

class _FocusEmptyLine extends StatelessWidget {
  final String message;

  const _FocusEmptyLine({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

Color _focusLevelColor(String level, LiflySemanticColors colors) {
  return switch (level.toLowerCase()) {
    'critical' || 'error' || 'danger' => colors.critical,
    'warning' || 'warn' => colors.warning,
    'success' || 'ok' => colors.success,
    'info' => colors.info,
    _ => colors.neutral,
  };
}

String _focusQueueSideTitle(HomeAttentionItem item) {
  if (item.level.toLowerCase() == 'critical') return '需要优先处理';
  final occurredAt = item.occurredAt;
  if (occurredAt != null) {
    final local = occurredAt.toLocal();
    return DateFormat('MM/dd HH:mm').format(local);
  }
  return _focusTypeLabel(item.type);
}

String _focusTypeLabel(String type) {
  return switch (type) {
    'task_overdue' => '已逾期',
    'task_due_today' => '今天截止',
    'budget_warning' => '预算预警',
    'sync_error' => '同步异常',
    'capture_confirmation' => 'AI 待确认',
    _ => type.replaceAll('_', ' '),
  };
}

String _focusEntityLabel(String entityType) {
  return switch (entityType) {
    'memo' => '备忘',
    'task' => '任务',
    'ledger_transaction' => '流水',
    'import_batch' => '导入批次',
    _ => '待处理内容',
  };
}

String _focusRelativeTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return DateFormat('HH:mm').format(local);
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day) {
    return '昨天';
  }
  return DateFormat('MM/dd').format(local);
}

double _focusRatio(double? raw) {
  if (raw == null || !raw.isFinite || raw <= 0) return 0;
  final normalized = raw > 1 ? raw / 100 : raw;
  return normalized.clamp(0, 1).toDouble();
}

NumberFormat _focusCurrencyFormatter(String currency) {
  final normalized = currency.trim().toUpperCase();
  return NumberFormat.currency(
    locale: 'zh_CN',
    symbol: normalized == 'CNY' || normalized.isEmpty ? '¥' : '$normalized ',
    decimalDigits: 0,
  );
}
