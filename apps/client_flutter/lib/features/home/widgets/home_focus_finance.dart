part of 'home_focus_view.dart';

class HomeFocusFinanceSection extends StatelessWidget {
  final HomeFinanceOverview finance;

  const HomeFocusFinanceSection({super.key, required this.finance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semanticColors;
    final formatter = _focusCurrencyFormatter(finance.currency);
    final budgetAmount = finance.budgetAmount ?? 0;
    final expenseRatio = budgetAmount > 0
        ? (finance.monthExpense / budgetAmount).clamp(0, 1).toDouble()
        : _focusRatio(finance.budgetProgress);
    final remainingRatio = budgetAmount > 0
        ? ((finance.budgetRemaining ?? 0) / budgetAmount).clamp(0, 1).toDouble()
        : 0.0;
    final topCategory = finance.categoryBreakdown
        .where((item) => item.direction == 'expense')
        .firstOrNull;

    return Column(
      key: const Key('home_focus_finance'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FocusSectionHeader(title: '本月收支', subtitle: '用占比判断，不展示装饰性图表'),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          child: Column(
            children: [
              _FocusMoneyLine(
                label: '支出',
                ratio: expenseRatio,
                color: semantic.critical,
                value: formatter.format(finance.monthExpense),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              _FocusMoneyLine(
                label: '预算余量',
                ratio: remainingRatio,
                color: semantic.success,
                value: finance.budgetState == 'not_configured'
                    ? '未设置'
                    : formatter.format(finance.budgetRemaining ?? 0),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              _FocusMoneyLine(
                label: topCategory?.categoryName ?? '主要分类',
                ratio: _focusRatio(topCategory?.ratio),
                color: semantic.warning,
                value: topCategory == null
                    ? '暂无'
                    : '${(_focusRatio(topCategory.ratio) * 100).round()}%',
              ),
            ],
          ),
        ),
        if (finance.insights.isNotEmpty) ...[
          const SizedBox(height: 12),
          _FocusInsightLine(insight: finance.insights.first),
        ],
      ],
    );
  }
}

class _FocusMoneyLine extends StatelessWidget {
  final String label;
  final double ratio;
  final Color color;
  final String value;

  const _FocusMoneyLine({
    required this.label,
    required this.ratio,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 45),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 9,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 5,
                color: theme.colorScheme.surfaceContainerHigh,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ratio.clamp(0, 1),
                  child: ColoredBox(color: color),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusInsightLine extends StatelessWidget {
  final HomeFinanceInsight insight;

  const _FocusInsightLine({required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _focusLevelColor(insight.level, theme.semanticColors);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: insight.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (insight.description.trim().isNotEmpty)
                  TextSpan(text: ' · ${insight.description.trim()}'),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
