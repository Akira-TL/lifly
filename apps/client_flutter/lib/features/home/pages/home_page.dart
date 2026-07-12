import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/home_overview_repository.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:client_flutter/features/search/pages/search_page.dart';
import 'package:client_flutter/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeOverview? _overview;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = HomeOverviewRepository(
        context.read<ApiClient>(),
        localCore: context.read<LocalCoreBridge>(),
        dataMode: context.read<LiflyDataMode>(),
      );
      final overview = await repository.load();
      if (!mounted) return;
      setState(() => _overview = overview);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '加载出错：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            tooltip: '全局搜索',
            icon: const Icon(Icons.search_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _loadOverview);
    }

    final overview = _overview;
    if (overview == null) {
      return _ErrorState(message: '首页概览为空', onRetry: _loadOverview);
    }

    return RefreshIndicator(
      onRefresh: _loadOverview,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSourceBanner(overview),
          const SizedBox(height: 12),
          _buildOverviewStats(overview.todayMetrics),
          const SizedBox(height: 16),
          _buildAttentionItems(overview.attentionItems),
          const SizedBox(height: 16),
          _buildMonthlyCard(overview.financeOverview),
          const SizedBox(height: 20),
          _buildWeeklyTrend(overview.dailyTrend),
          const SizedBox(height: 20),
          _buildRecentActivity(overview.recentActivity),
        ],
      ),
    );
  }

  Widget _buildSourceBanner(HomeOverview overview) {
    final theme = Theme.of(context);
    final sourceLabel = overview.sourceMode == 'local' ? '本地计算' : '云端兼容';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              overview.sourceMode == 'local'
                  ? Icons.storage_outlined
                  : Icons.cloud_outlined,
              color: theme.colorScheme.primary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$sourceLabel · ${DateFormat('MM/dd HH:mm').format(overview.generatedAt.toLocal())}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              overview.schemaVersion,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewStats(HomeTodayMetrics metrics) {
    return Row(
      children: [
        Expanded(
          child: _CountCard(
            label: '备忘',
            value: metrics.memoTotal,
            icon: Icons.note_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CountCard(
            label: '待办',
            value: metrics.taskTodo,
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CountCard(
            label: '今天',
            value: metrics.taskDueToday,
            icon: Icons.today_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildAttentionItems(List<HomeAttentionItem> items) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '今日关注',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const _EmptyCard(message: '暂无紧急事项')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: items.map((item) {
                final isCritical = item.level == 'critical';
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: isCritical
                        ? Colors.red.withAlpha(30)
                        : Colors.orange.withAlpha(30),
                    child: Icon(
                      isCritical
                          ? Icons.priority_high
                          : Icons.warning_amber_outlined,
                      color: isCritical ? Colors.red : Colors.orange,
                    ),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(item.description ?? item.type),
                  trailing: item.occurredAt == null
                      ? null
                      : Text(
                          _formatShortDate(item.occurredAt!.toIso8601String()),
                        ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildMonthlyCard(HomeFinanceOverview finance) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${DateFormat('M月').format(DateTime.now())}收支汇总',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (finance.budgetState == 'not_configured')
                  Text('未设置预算', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: '收入',
                    amount: finance.monthIncome,
                    color: Colors.green,
                    icon: Icons.arrow_upward,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _SummaryItem(
                    label: '支出',
                    amount: finance.monthExpense,
                    color: Colors.red,
                    icon: Icons.arrow_downward,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyTrend(List<HomeDailyTrendItem> data) {
    final theme = Theme.of(context);
    if (data.isEmpty) return const _EmptyCard(message: '暂无本周趋势数据');

    final maxAmount = data
        .map((item) => item.total)
        .fold<double>(0, (max, value) => value > max ? value : max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '本周趋势',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((item) {
                  final amount = item.total;
                  final fraction = maxAmount > 0 ? amount / maxAmount : 0.0;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (amount > 0)
                          Text(
                            amount >= 10000
                                ? '${(amount / 10000).toStringAsFixed(1)}w'
                                : amount.toStringAsFixed(0),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: 10,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Container(
                          width: 24,
                          height: (fraction * 100).clamp(2, 100),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(180),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _shortDayLabel(item.day),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity(List<HomeActivityItem> items) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近活动',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const _EmptyCard(message: '暂无最近活动')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: items.take(8).map((item) {
                final isLedger = item.entityType == 'ledger_transaction';
                final isExpense = item.direction == 'expense';
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: _activityColor(
                      item,
                      isExpense,
                    ).withAlpha(30),
                    child: Icon(
                      _activityIcon(item),
                      color: _activityColor(item, isExpense),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.subtitle?.trim().isNotEmpty == true
                        ? item.subtitle!.trim()
                        : _formatShortDate(item.occurredAt.toIso8601String()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isLedger && item.amount != null
                      ? Text(
                          '${isExpense ? '-' : '+'}¥${item.amount!.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isExpense ? Colors.red : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Text(
                          _formatShortDate(item.occurredAt.toIso8601String()),
                        ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  IconData _activityIcon(HomeActivityItem item) {
    return switch (item.entityType) {
      'memo' => Icons.note_outlined,
      'task' => Icons.check_circle_outline,
      'ledger_transaction' =>
        item.direction == 'income'
            ? Icons.attach_money
            : Icons.shopping_bag_outlined,
      _ => Icons.history,
    };
  }

  Color _activityColor(HomeActivityItem item, bool isExpense) {
    return switch (item.entityType) {
      'memo' => Theme.of(context).colorScheme.primary,
      'task' => Colors.orange,
      'ledger_transaction' => isExpense ? Colors.red : Colors.green,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  String _shortDayLabel(DateTime day) {
    const weekDays = ['', '一', '二', '三', '四', '五', '六', '日'];
    return '周${weekDays[day.toLocal().weekday]}';
  }

  String _formatShortDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return DateFormat('MM/dd').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _CountCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value.toString(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '¥${amount.toStringAsFixed(2)}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;

  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
