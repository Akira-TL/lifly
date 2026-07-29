part of 'home_dashboard_view.dart';

class _FinancePanel extends StatelessWidget {
  final HomeFinanceOverview finance;

  const _FinancePanel({required this.finance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semanticColors;
    final formatter = _currencyFormatter(finance.currency);
    final budgetConfigured = finance.budgetState != 'not_configured' &&
        finance.budgetAmount != null &&
        finance.budgetAmount! > 0;
    final budgetProgress = _normalizedRatio(finance.budgetProgress ?? 0);

    return WorkspacePanel(
      key: const Key('home_finance_panel'),
      title: '${DateFormat('M月').format(DateTime.now())}收支',
      subtitle: '金额、预算和分类占比放在同一个判断区',
      trailing: Text(
        budgetConfigured ? '预算 ${(budgetProgress * 100).round()}%' : '未设置预算',
        style: theme.textTheme.labelMedium?.copyWith(
          color: budgetConfigured
              ? (budgetProgress >= 0.9 ? semantic.warning : semantic.success)
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _FinanceValue(
                  label: '本月支出',
                  value: formatter.format(finance.monthExpense),
                  color: semantic.critical,
                ),
              ),
              Expanded(
                child: _FinanceValue(
                  label: '本月收入',
                  value: formatter.format(finance.monthIncome),
                  color: semantic.success,
                ),
              ),
              Expanded(
                child: _FinanceValue(
                  label: '流水',
                  value: '${finance.transactionCount} 笔',
                  color: semantic.info,
                ),
              ),
            ],
          ),
          if (budgetConfigured) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '预算已用 ${formatter.format(finance.budgetUsed ?? 0)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  '剩余 ${formatter.format(finance.budgetRemaining ?? 0)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: budgetProgress,
              minHeight: 6,
              color: budgetProgress >= 0.9 ? semantic.warning : semantic.info,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
          if (finance.categoryBreakdown.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              '主要支出分类',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final category in finance.categoryBreakdown.take(5))
              _CategoryRow(
                category: category,
                formatter: formatter,
                color: semantic.info,
              ),
          ],
          if (finance.insights.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 8),
            for (final insight in finance.insights.take(3))
              _FinanceInsightRow(insight: insight),
          ],
          if (!budgetConfigured &&
              finance.categoryBreakdown.isEmpty &&
              finance.insights.isEmpty)
            const WorkspaceEmptyRow(
              icon: Icons.account_balance_wallet_outlined,
              message: '记录流水后，这里会显示预算、分类和消费洞察',
            ),
        ],
      ),
    );
  }
}

class _FinanceValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _FinanceValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final HomeFinanceCategory category;
  final NumberFormat formatter;
  final Color color;

  const _CategoryRow({
    required this.category,
    required this.formatter,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = _normalizedRatio(category.ratio);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                formatter.format(category.amount),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 38,
                child: Text(
                  '${(ratio * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 3,
            color: color,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }
}

class _FinanceInsightRow extends StatelessWidget {
  final HomeFinanceInsight insight;

  const _FinanceInsightRow({required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _levelColor(insight.level, theme.semanticColors);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: WorkspaceStatusDot(color: color, size: 7),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (insight.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    insight.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
