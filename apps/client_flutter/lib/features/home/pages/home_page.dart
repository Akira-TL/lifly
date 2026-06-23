import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final response = await api.get('/dashboard');

      if (!mounted) return;

      if (response['success'] == true) {
        setState(() {
          _data = response['data'] as Map<String, dynamic>?;
        });
      } else {
        setState(() {
          _error = response['message'] as String? ?? '加载失败';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载出错: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('首页')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadDashboard,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final monthlyIncome =
        (_data?['monthly_income'] as num?)?.toDouble() ?? 0;
    final monthlyExpense =
        (_data?['monthly_expense'] as num?)?.toDouble() ?? 0;
    final weeklyTrend =
        (_data?['weekly_trend'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final recentTransactions =
        (_data?['recent_transactions'] as List?)
            ?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMonthlyCard(monthlyIncome, monthlyExpense),
          const SizedBox(height: 20),
          _buildWeeklyTrend(weeklyTrend),
          const SizedBox(height: 20),
          _buildRecentTransactions(recentTransactions),
        ],
      ),
    );
  }

  Widget _buildMonthlyCard(double income, double expense) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('M月').format(DateTime.now())}收支汇总',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: '收入',
                    amount: income,
                    color: Colors.green,
                    icon: Icons.arrow_upward,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _SummaryItem(
                    label: '支出',
                    amount: expense,
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

  Widget _buildWeeklyTrend(List<Map<String, dynamic>> data) {
    final theme = Theme.of(context);

    if (data.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text('暂无本周趋势数据',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    final maxAmount = data
        .map((d) => (d['amount'] as num?)?.toDouble() ?? 0)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('本周趋势',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((d) {
                  final amount =
                      (d['amount'] as num?)?.toDouble() ?? 0;
                  final label = d['day'] as String? ??
                      d['date'] as String? ??
                      '';
                  final fraction =
                      maxAmount > 0 ? amount / maxAmount : 0.0;
                  final barHeight = fraction * 100;

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
                          height: barHeight.clamp(0, 100),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withAlpha(180),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _shortDayLabel(label),
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

  String _shortDayLabel(String raw) {
    if (raw.length <= 3) return raw;
    // Try to extract short day name from ISO date
    try {
      final dt = DateTime.parse(raw);
      final weekDays = ['', '一', '二', '三', '四', '五', '六', '日'];
      return '周${weekDays[dt.weekday]}';
    } catch (_) {
      return raw.substring(0, 3);
    }
  }

  Widget _buildRecentTransactions(List<Map<String, dynamic>> transactions) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近交易',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('暂无交易记录',
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: transactions.take(5).map((tx) {
                final direction =
                    tx['direction'] as String? ?? 'expense';
                final amount =
                    (tx['amount'] as num?)?.toDouble() ?? 0;
                final merchant = tx['merchant'] as String?;
                final note = tx['note'] as String?;
                final occurredAt = tx['occurred_at'] as String?;
                final isExpense = direction == 'expense';

                String dateLabel = '';
                if (occurredAt != null) {
                  try {
                    dateLabel = DateFormat('MM/dd')
                        .format(DateTime.parse(occurredAt));
                  } catch (_) {
                    dateLabel = occurredAt;
                  }
                }

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: isExpense
                        ? Colors.red.withAlpha(30)
                        : Colors.green.withAlpha(30),
                    child: Icon(
                      isExpense
                          ? Icons.shopping_bag_outlined
                          : Icons.attach_money,
                      color: isExpense ? Colors.red : Colors.green,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    merchant ?? note ?? '未知',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: note != null && note != merchant
                      ? Text(note,
                          maxLines: 1, overflow: TextOverflow.ellipsis)
                      : (dateLabel.isNotEmpty
                          ? Text(dateLabel,
                              style: theme.textTheme.bodySmall)
                          : null),
                  trailing: Text(
                    '${isExpense ? '-' : '+'}¥${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: isExpense ? Colors.red : Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
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
              Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: color)),
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
