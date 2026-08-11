import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/import_export_models.dart';
import 'package:client_flutter/data/repositories/import_export_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum ImportPreviewStatusFilter {
  all(null, '全部'),
  pending('pending', '待导入'),
  ignored('ignored', '已忽略'),
  error('error', '错误'),
  duplicate('duplicate', '重复'),
  imported('imported', '已导入');

  const ImportPreviewStatusFilter(this.value, this.label);

  final String? value;
  final String label;
}

class BillImportPreviewPage extends StatefulWidget {
  final String batchId;
  final ImportExportRepository? repository;

  const BillImportPreviewPage({
    super.key,
    required this.batchId,
    this.repository,
  });

  @override
  State<BillImportPreviewPage> createState() => _BillImportPreviewPageState();
}

class _BillImportPreviewPageState extends State<BillImportPreviewPage> {
  static const _pageSize = 50;

  final List<ImportPreviewRow> _rows = [];
  ImportBatch? _batch;
  ImportPreviewStatusFilter _filter = ImportPreviewStatusFilter.all;
  int _total = 0;
  int _offset = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _committing = false;
  ImportCommitResult? _commitResult;
  String? _error;
  String? _commitError;

  ImportExportRepository get _repository =>
      widget.repository ?? ImportExportRepository(context.read<ApiClient>());

  List<ImportPreviewRow> get _filteredRows {
    final status = _filter.value;
    if (status == null) return _rows;
    return _rows.where((row) => row.status == status).toList(growable: false);
  }

  bool get _hasMore => _offset < _total;

  bool get _canCommit {
    final status = _batch?.status ?? 'preview';
    return !_committing && _commitResult == null && status == 'preview';
  }

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows.clear();
      _offset = 0;
      _total = 0;
    });

    try {
      final page = await _repository.previewDetail(
        widget.batchId,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _batch = page.batch;
        _rows.addAll(page.items);
        _total = page.total;
        _offset = page.nextOffset;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '加载预览失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });

    try {
      final page = await _repository.previewDetail(
        widget.batchId,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _batch = page.batch;
        _rows.addAll(page.items);
        _total = page.total;
        _offset = page.nextOffset;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '加载更多失败：$error');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _confirmAndCommit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认提交导入？'),
        content: const Text('提交后会写入记账流水。重复行、错误行和忽略行会按服务端规则跳过。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _committing = true;
      _commitError = null;
    });

    try {
      final result = await _repository.commit(widget.batchId);
      if (!mounted) return;
      setState(() => _commitResult = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _commitError = '提交导入失败：$error');
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入预览')),
      body: RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BatchSummaryCard(
              batchId: widget.batchId,
              batch: _batch,
              loadedRows: _rows.length,
              totalRows: _total,
            ),
            const SizedBox(height: 12),
            _CommitCard(
              batch: _batch,
              result: _commitResult,
              error: _commitError,
              committing: _committing,
              canCommit: _canCommit,
              onCommit: _confirmAndCommit,
            ),
            const SizedBox(height: 12),
            _FilterCard(
              selected: _filter,
              rows: _rows,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!, onRetry: _loadFirstPage),
            ],
            const SizedBox(height: 12),
            if (_loading && _rows.isEmpty)
              const Center(child: CircularProgressIndicator())
            else
              _PreviewRowsCard(rows: _filteredRows),
            const SizedBox(height: 12),
            _LoadMoreButton(
              hasMore: _hasMore,
              loadingMore: _loadingMore,
              onLoadMore: _loadMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchSummaryCard extends StatelessWidget {
  final String batchId;
  final ImportBatch? batch;
  final int loadedRows;
  final int totalRows;

  const _BatchSummaryCard({
    required this.batchId,
    required this.batch,
    required this.loadedRows,
    required this.totalRows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBatch = batch;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '预览批次',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText('导入编号：$batchId'),
            if (currentBatch != null) ...[
              Text('文件：${currentBatch.filename ?? '-'}'),
              Text('状态：${currentBatch.status}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(label: '总行数', value: currentBatch.totalRows),
                  _StatChip(label: '有效', value: currentBatch.validRows),
                  _StatChip(label: '重复', value: currentBatch.duplicateRows),
                  _StatChip(label: '已加载', value: loadedRows),
                ],
              ),
            ] else ...[
              Text('已加载：$loadedRows / $totalRows'),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommitCard extends StatelessWidget {
  final ImportBatch? batch;
  final ImportCommitResult? result;
  final String? error;
  final bool committing;
  final bool canCommit;
  final VoidCallback onCommit;

  const _CommitCard({
    required this.batch,
    required this.result,
    required this.error,
    required this.committing,
    required this.canCommit,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentResult = result;
    final currentError = error;
    final status = batch?.status ?? 'preview';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.playlist_add_check,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '提交导入',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('当前批次状态：${_statusLabel(status)}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canCommit ? onCommit : null,
              icon: committing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all_outlined),
              label: Text(committing ? '提交中...' : '提交导入'),
            ),
            if (currentError != null) ...[
              const SizedBox(height: 12),
              Text(
                currentError,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (currentResult != null) ...[
              const SizedBox(height: 12),
              Text(
                '提交结果：${_statusLabel(currentResult.status)}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(label: '已导入', value: currentResult.imported),
                  _StatChip(label: '重复', value: currentResult.duplicates),
                  _StatChip(label: '错误', value: currentResult.errors),
                  _StatChip(label: '跳过', value: currentResult.skipped),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'preview' => '预览中',
      'committed' => '已提交',
      'rolled_back' => '已回滚',
      _ => status,
    };
  }
}

class _FilterCard extends StatelessWidget {
  final ImportPreviewStatusFilter selected;
  final List<ImportPreviewRow> rows;
  final ValueChanged<ImportPreviewStatusFilter> onSelected;

  const _FilterCard({
    required this.selected,
    required this.rows,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('状态筛选', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ImportPreviewStatusFilter.values
                  .map((filter) {
                    return FilterChip(
                      label: Text('${filter.label}（${_count(filter)}）'),
                      selected: selected == filter,
                      onSelected: (_) => onSelected(filter),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  int _count(ImportPreviewStatusFilter filter) {
    final status = filter.value;
    if (status == null) return rows.length;
    return rows.where((row) => row.status == status).length;
  }
}

class _PreviewRowsCard extends StatelessWidget {
  final List<ImportPreviewRow> rows;

  const _PreviewRowsCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('当前筛选下暂无预览行')),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.receipt_long_outlined),
            title: Text('预览行'),
            subtitle: Text('金额、方向、商户、时间、备注与错误原因'),
          ),
          const Divider(height: 1),
          ...rows.map(_PreviewRowTile.new),
        ],
      ),
    );
  }
}

class _PreviewRowTile extends StatelessWidget {
  final ImportPreviewRow row;

  const _PreviewRowTile(this.row);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = row.parsedData ?? const <String, dynamic>{};
    final merchant = _text(parsed['merchant'], fallback: '未解析商户');
    final direction = _directionLabel(
      _text(parsed['direction'], fallback: '-'),
    );
    final amount = _text(parsed['amount'], fallback: '-');
    final occurredAt = _text(parsed['occurred_at'], fallback: '-');
    final note = _text(parsed['note'] ?? parsed['category_hint'], fallback: '');
    final error = row.errorMessage;

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Text('#${row.rowIndex}'),
      title: Text('$merchant · $amount'),
      subtitle: Text('$direction · $occurredAt · ${_statusLabel(row.status)}'),
      trailing: _StatusBadge(status: row.status),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailLine(label: '方向', value: direction),
              _DetailLine(label: '金额', value: amount),
              _DetailLine(label: '商户', value: merchant),
              _DetailLine(label: '时间', value: occurredAt),
              _DetailLine(label: '备注', value: note.isEmpty ? '-' : note),
              if (error != null && error.isNotEmpty)
                _DetailLine(
                  label: '原因',
                  value: error,
                  color: theme.colorScheme.error,
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _text(Object? value, {required String fallback}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _directionLabel(String value) {
    return switch (value) {
      'expense' => '支出',
      'income' => '收入',
      'transfer' => '转账',
      _ => value,
    };
  }

  String _statusLabel(String value) {
    return switch (value) {
      'pending' => '待导入',
      'ignored' => '已忽略',
      'error' => '错误',
      'duplicate' => '重复',
      'imported' => '已导入',
      _ => value,
    };
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (status) {
      'error' => theme.colorScheme.errorContainer,
      'duplicate' => theme.colorScheme.tertiaryContainer,
      'ignored' => theme.colorScheme.surfaceContainerHighest,
      _ => theme.colorScheme.primaryContainer,
    };
    return Chip(label: Text(status), backgroundColor: color);
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _DetailLine({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$label：$value', style: TextStyle(color: color)),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  const _LoadMoreButton({
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasMore) return const Center(child: Text('已加载全部预览行'));
    return Center(
      child: OutlinedButton.icon(
        onPressed: loadingMore ? null : onLoadMore,
        icon: loadingMore
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text(loadingMore ? '加载中...' : '加载更多'),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
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

class _StatChip extends StatelessWidget {
  final String label;
  final int value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label：$value'));
  }
}
