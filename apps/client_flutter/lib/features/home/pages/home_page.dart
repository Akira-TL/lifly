import 'package:client_flutter/data/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
        setState(() => _data = response['data'] as Map<String, dynamic>? ?? {});
      } else {
        setState(() => _error = response['error'] as String? ?? '加载失败');
      }
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
      appBar: AppBar(title: const Text('首页')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorState(message: _error!, onRetry: _loadDashboard);

    final dashboard = _data ?? {};
    final monthlyIncome = _numValue(dashboard, ['month_income', 'monthly_income']);
    final monthlyExpense = _numValue(dashboard, ['month_expense', 'monthly_expense']);
    final memoTotal = _intValue(dashboard, 'memo_total');
    final taskTodo = _intValue(dashboard, 'task_todo');
    final taskTotal = _intValue(dashboard, 'task_total');
    final trend = _listOfMaps(dashboard['daily_trend'] ?? dashboard['weekly_trend']);
    final recentTransactions = _listOfMaps(dashboard['recent_transactions']);

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverviewStats(memoTotal: memoTotal, taskTodo: taskTodo, taskTotal: taskTotal),
          const SizedBox(height: 16),
          _buildMonthlyCard(monthlyIncome, monthlyExpense),
          const SizedBox(height: 20),
          _buildWeeklyTrend(trend),
          const SizedBox(height: 20),
          _buildRecentTransactions(recentTransactions),
        ],
      ),
    );
  }

  Widget _buildOverviewStats({required int memoTotal, required int taskTodo, required int taskTotal}) {
    return Row(
      children: [
        Expanded(child: _CountCard(label: '备忘', value: memoTotal, icon: Icons.note_outlined)),
        const SizedBox(width: 12),
        Expanded(child: _CountCard(label: '待办', value: taskTodo, icon: Icons.check_circle_outline)),
        const SizedBox(width: 12),
        Expanded(child: _CountCard(label: '任务总数', value: taskTotal, icon: Icons.list_alt_outlined)),
      ],
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
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
    if (data.isEmpty) return _EmptyCard(message: '暂无本周趋势数据');

    final maxAmount = data
        .map((item) => _numValue(item, ['amount', 'total']))
        .fold<double>(0, (max, value) => value > max ? value : max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('本周趋势', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((item) {
                  final amount = _numValue(item, ['amount', 'total']);
                  final label = item['day'] as String? ?? item['date'] as String? ?? '';
                  final fraction = maxAmount > 0 ? amount / maxAmount : 0.0;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (amount > 0)
                          Text(
                            amount >= 10000 ? '${(amount / 10000).toStringAsFixed(1)}w' : amount.toStringAsFixed(0),
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
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_shortDayLabel(label), style: theme.textTheme.labelSmall?.copyWith(fontSize: 11)),
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

  Widget _buildRecentTransactions(List<Map<String, dynamic>> transactions) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近交易', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          const _EmptyCard(message: '暂无交易记录')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: transactions.take(5).map((tx) {
                final direction = tx['direction'] as String? ?? 'expense';
                final amount = _numValue(tx, ['amount']);
                final merchant = tx['merchant'] as String?;
                final note = tx['note'] as String?;
                final occurredAt = tx['occurred_at'] as String?;
                final isExpense = direction == 'expense';
                final dateLabel = _formatShortDate(occurredAt);

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: isExpense ? Colors.red.withAlpha(30) : Colors.green.withAlpha(30),
                    child: Icon(
                      isExpense ? Icons.shopping_bag_outlined : Icons.attach_money,
                      color: isExpense ? Colors.red : Colors.green,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    merchant ?? note ?? '未知',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: note != null && note != merchant ? Text(note, maxLines: 1, overflow: TextOverflow.ellipsis) : Text(dateLabel),
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

  String _shortDayLabel(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw);
      const weekDays = ['', '一', '二', '三', '四', '五', '六', '日'];
      return '周${weekDays[dt.weekday]}';
    } catch (_) {
      return raw.length <= 3 ? raw : raw.substring(0, 3);
    }
  }

  String _formatShortDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return DateFormat('MM/dd').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  static double _numValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toDouble();
    }
    return 0;
  }

  static int _intValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is num ? value.toInt() : 0;
  }

  static List<Map<String, dynamic>> _listOfMaps(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) => item.cast<String, dynamic>()).toList();
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _CountCard({required this.label, required this.value, required this.icon});

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
            Text(value.toString(), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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

  const _SummaryItem({required this.label, required this.amount, required this.color, required this.icon});

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
              Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '¥${amount.toStringAsFixed(2)}',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color),
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
          child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
