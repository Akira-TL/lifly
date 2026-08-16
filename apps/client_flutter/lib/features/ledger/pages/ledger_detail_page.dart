import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/ledger_repository.dart';
import 'package:client_flutter/domain/entities/ledger_transaction.dart';
import 'package:client_flutter/shared/errors/user_facing_error.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class LedgerDetailPage extends StatefulWidget {
  final String transactionId;
  final LedgerTransaction? initialTransaction;

  const LedgerDetailPage({
    super.key,
    required this.transactionId,
    this.initialTransaction,
  });

  @override
  State<LedgerDetailPage> createState() => _LedgerDetailPageState();
}

class _LedgerDetailPageState extends State<LedgerDetailPage> {
  late final LedgerRepository _repo;
  LedgerTransaction? _transaction;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = LedgerRepository(
      context.read<ApiClient>(),
      localCore: context.read<LocalCoreBridge>(),
      dataMode: context.read<LiflyDataMode>(),
      sessions: context.read<AuthSessionStore>(),
    );
    _transaction = widget.initialTransaction;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _transaction == null;
      _error = null;
    });
    try {
      final transaction = await _repo.get(widget.transactionId);
      if (!mounted) return;
      setState(() => _transaction = transaction);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(
        () => _error = userFacingFailure(
          action: '加载账单详情',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editTransaction() async {
    final transaction = _transaction;
    if (transaction == null) return;
    final draft = await showDialog<_LedgerEditDraft>(
      context: context,
      builder: (_) => _LedgerEditDialog(transaction: transaction),
    );
    if (draft == null) return;

    setState(() => _isSaving = true);
    try {
      final updated = await _repo.update(transaction.id, {
        'direction': draft.direction,
        'amount': draft.amount,
        'currency': transaction.currency,
        'merchant': draft.merchant.isEmpty ? null : draft.merchant,
        'note': draft.note.isEmpty ? null : draft.note,
        'category_id': transaction.categoryId,
        'occurred_at': transaction.occurredAt.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      setState(() => _transaction = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('账单已更新')));
    } catch (error, stackTrace) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingFailure(
              action: '更新账单',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeTransaction() async {
    final transaction = _transaction;
    if (transaction == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账单？'),
        content: const Text('该账单将不再出现在列表中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _repo.delete(transaction.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingFailure(
              action: '删除账单',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = _transaction;
    final color = transaction?.isExpense == true ? Colors.red : Colors.green;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账单详情'),
        actions: [
          IconButton(
            tooltip: '编辑账单',
            onPressed: _isSaving ? null : _editTransaction,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除账单',
            onPressed: _isSaving ? null : _removeTransaction,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: '正在加载账单')
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : transaction == null
          ? const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: '未找到账单',
              subtitle: '该账单不存在或已被移除。',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    transaction.amountText,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    transaction.merchant ?? transaction.note ?? '未知交易',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 20),
                  _DetailRow(
                    label: '类型',
                    value: _ledgerDirectionLabel(transaction.direction),
                  ),
                  _DetailRow(label: '币种', value: transaction.currency),
                  _DetailRow(
                    label: '分类',
                    value: transaction.categoryId ?? '未分类',
                  ),
                  _DetailRow(
                    label: '来源',
                    value: _ledgerSourceLabel(transaction.source),
                  ),
                  _DetailRow(
                    label: '发生时间',
                    value: DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(transaction.occurredAt.toLocal()),
                  ),
                  _DetailRow(
                    label: '创建时间',
                    value: DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(transaction.createdAt.toLocal()),
                  ),
                  _DetailRow(label: '备注', value: transaction.note ?? '无'),
                ],
              ),
            ),
    );
  }
}

String _ledgerDirectionLabel(String direction) {
  return switch (direction) {
    'expense' => '支出',
    'income' => '收入',
    'transfer' => '转账',
    _ => '其他',
  };
}

String _ledgerSourceLabel(String source) {
  return switch (source) {
    'local' => '本地记录',
    'manual' || 'flutter' => '手动记录',
    'ai' || 'capture' => 'AI 记录',
    'import' => '账单导入',
    _ => '其他来源',
  };
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _LedgerEditDraft {
  final String direction;
  final double amount;
  final String merchant;
  final String note;

  const _LedgerEditDraft({
    required this.direction,
    required this.amount,
    required this.merchant,
    required this.note,
  });
}

class _LedgerEditDialog extends StatefulWidget {
  final LedgerTransaction transaction;

  const _LedgerEditDialog({required this.transaction});

  @override
  State<_LedgerEditDialog> createState() => _LedgerEditDialogState();
}

class _LedgerEditDialogState extends State<_LedgerEditDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  late final TextEditingController _noteController;
  late String _direction;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.transaction.amount.toStringAsFixed(2),
    );
    _merchantController = TextEditingController(
      text: widget.transaction.merchant ?? '',
    );
    _noteController = TextEditingController(
      text: widget.transaction.note ?? '',
    );
    _direction = widget.transaction.direction;
  }

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
      title: const Text('编辑账单'),
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
              onSelectionChanged: (selected) =>
                  setState(() => _direction = selected.first),
            ),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '金额',
                errorText: _amountError,
              ),
              onChanged: (_) {
                if (_amountError != null) setState(() => _amountError = null);
              },
            ),
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(labelText: '商户/来源'),
            ),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: '备注'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountController.text.trim());
            if (amount == null || amount <= 0) {
              setState(() => _amountError = '请输入大于 0 的金额');
              return;
            }
            Navigator.pop(
              context,
              _LedgerEditDraft(
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
