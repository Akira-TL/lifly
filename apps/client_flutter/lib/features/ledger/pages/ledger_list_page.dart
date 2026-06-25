import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/ledger_repository.dart';
import 'package:client_flutter/domain/entities/ledger_transaction.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class LedgerListPage extends StatefulWidget {
  const LedgerListPage({super.key});

  @override
  State<LedgerListPage> createState() => _LedgerListPageState();
}

class _LedgerListPageState extends State<LedgerListPage> {
  late final LedgerRepository _repo;
  final List<LedgerTransaction> _items = [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = LedgerRepository(context.read<ApiClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _repo.list(limit: 50),
        _repo.summary(),
      ]);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(results[0] as List<LedgerTransaction>);
        _summary = results[1] as Map<String, dynamic>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '账单加载失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createTransaction() async {
    final draft = await showDialog<_LedgerDraft>(context: context, builder: (_) => const _LedgerEditorDialog());
    if (draft == null) return;

    setState(() => _isCreating = true);
    try {
      await _repo.create({
        'direction': draft.direction,
        'amount': draft.amount,
        'currency': 'CNY',
        'merchant': draft.merchant.isEmpty ? null : draft.merchant,
        'note': draft.note.isEmpty ? null : draft.note,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'source': 'flutter',
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建账单失败：$error')));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记账')),
      body: AsyncContentScaffold(
        isLoading: _isLoading,
        error: _error,
        isEmpty: _items.isEmpty,
        onRefresh: _load,
        emptyIcon: Icons.account_balance_wallet_outlined,
        emptyTitle: '还没有账单',
        emptySubtitle: '点击右下角记一笔，先打通真实 API 写入。',
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _SummaryCard(summary: _summary),
            const SizedBox(height: 12),
            ..._items.map((tx) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LedgerTile(transaction: tx),
                )),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreating ? null : _createTransaction,
        icon: _isCreating
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> summary;

  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final income = _num(summary['income_total']);
    final expense = _num(summary['expense_total']);
    final count = summary['transaction_count'] is num ? (summary['transaction_count'] as num).toInt() : 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: _SummaryMetric(label: '收入', value: '¥${income.toStringAsFixed(2)}', color: Colors.green)),
            Expanded(child: _SummaryMetric(label: '支出', value: '¥${expense.toStringAsFixed(2)}', color: Colors.red)),
            Expanded(child: _SummaryMetric(label: '笔数', value: count.toString(), color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }

  static double _num(Object? value) => value is num ? value.toDouble() : 0;
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryMetric({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _LedgerTile extends StatelessWidget {
  final LedgerTransaction transaction;

  const _LedgerTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.isExpense;
    final color = isExpense ? Colors.red : Colors.green;
    final dateLabel = DateFormat('MM/dd HH:mm').format(transaction.occurredAt.toLocal());

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(isExpense ? Icons.shopping_bag_outlined : Icons.attach_money, color: color),
        ),
        title: Text(transaction.merchant ?? transaction.note ?? '未知交易', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [if (transaction.note != null) transaction.note!, dateLabel, transaction.source].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          transaction.amountText,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _LedgerDraft {
  final String direction;
  final double amount;
  final String merchant;
  final String note;

  const _LedgerDraft({required this.direction, required this.amount, required this.merchant, required this.note});
}

class _LedgerEditorDialog extends StatefulWidget {
  const _LedgerEditorDialog();

  @override
  State<_LedgerEditorDialog> createState() => _LedgerEditorDialogState();
}

class _LedgerEditorDialogState extends State<_LedgerEditorDialog> {
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _noteController = TextEditingController();
  String _direction = 'expense';

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('记一笔'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('支出')),
                ButtonSegment(value: 'income', label: Text('收入')),
              ],
              selected: {_direction},
              onSelectionChanged: (selected) => setState(() => _direction = selected.first),
            ),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '金额'),
            ),
            TextField(controller: _merchantController, decoration: const InputDecoration(labelText: '商户/来源')),
            TextField(controller: _noteController, decoration: const InputDecoration(labelText: '备注')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountController.text.trim());
            if (amount == null || amount <= 0) return;
            Navigator.pop(
              context,
              _LedgerDraft(
                direction: _direction,
                amount: amount,
                merchant: _merchantController.text.trim(),
                note: _noteController.text.trim(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
