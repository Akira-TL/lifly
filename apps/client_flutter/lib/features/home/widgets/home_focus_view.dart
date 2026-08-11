import 'package:client_flutter/app/theme/lifly_semantic_colors.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:client_flutter/features/home/widgets/home_task_focus_visuals.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

part 'home_focus_agenda.dart';
part 'home_focus_finance.dart';

class HomeFocusView extends StatelessWidget {
  static const _agendaBreakpoint = 860.0;

  final HomeOverview overview;
  final Future<void> Function() onRefresh;
  final Future<void> Function(HomeAttentionItem item) onCompleteTask;

  const HomeFocusView({
    super.key,
    required this.overview,
    required this.onRefresh,
    required this.onCompleteTask,
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
                      _FocusQueueSection(
                        items: overview.attentionItems,
                        onCompleteTask: onCompleteTask,
                      ),
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
              _FocusQueueSection(
                items: overview.attentionItems,
                onCompleteTask: onCompleteTask,
              ),
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
  final Future<void> Function(HomeAttentionItem item) onCompleteTask;

  const _FocusQueueSection({required this.items, required this.onCompleteTask});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid = constraints.maxWidth >= 620;
        final gridColumns = constraints.maxWidth >= 820 ? 3 : 2;
        final visibleItems = items
            .take(useGrid ? 6 : 3)
            .toList(growable: false);
        return Column(
          key: const Key('home_focus_queue'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FocusSectionHeader(
              title: visibleItems.isEmpty
                  ? '今天没有需要优先处理的事项'
                  : '先处理这 ${visibleItems.length} 件事',
              actionLabel: items.length > visibleItems.length
                  ? '还有 ${items.length - visibleItems.length} 项'
                  : null,
            ),
            if (visibleItems.isEmpty)
              const _FocusEmptyLine(message: '当前没有需要优先处理的任务')
            else if (useGrid)
              GridView.builder(
                key: const Key('home_focus_queue_grid'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visibleItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridColumns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 60,
                ),
                itemBuilder: (context, index) => HomeTaskFocusTile(
                  item: visibleItems[index],
                  onCompleteTask: onCompleteTask,
                  keyPrefix: 'home_focus',
                ),
              )
            else
              Column(
                children: [
                  for (var index = 0; index < visibleItems.length; index++) ...[
                    HomeTaskFocusTile(
                      item: visibleItems[index],
                      onCompleteTask: onCompleteTask,
                      keyPrefix: 'home_focus',
                    ),
                    if (index != visibleItems.length - 1)
                      const SizedBox(height: 6),
                  ],
                ],
              ),
          ],
        );
      },
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
  final String? subtitle;
  final String? actionLabel;

  const _FocusSectionHeader({
    required this.title,
    this.subtitle,
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
                if (subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
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

String _focusItemDetail(HomeAttentionItem item, {bool includeTime = false}) {
  final rawDescription = item.description?.trim() ?? '';
  final statusLabel = _focusTypeLabel(item.type);
  final genericDescription =
      rawDescription.isEmpty ||
      rawDescription == '任务已逾期' ||
      rawDescription == '今天截止' ||
      rawDescription == statusLabel;
  final base = genericDescription
      ? _focusEntityLabel(item.entityType)
      : rawDescription;
  if (!includeTime || item.occurredAt == null) return base;
  return '$base · ${DateFormat('MM/dd HH:mm').format(item.occurredAt!.toLocal())}';
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
