import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/import_export_models.dart';
import 'package:client_flutter/data/repositories/import_export_repository.dart';
import 'package:client_flutter/features/import_export/pages/bill_import_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum ImportBatchStatusFilter {
  all(null, '全部'),
  preview('preview', '预览中'),
  committed('committed', '已提交'),
  rolledBack('rolled_back', '已回滚');

  const ImportBatchStatusFilter(this.value, this.label);

  final String? value;
  final String label;
}

class ImportBatchesPage extends StatefulWidget {
  final ImportExportRepository? repository;

  const ImportBatchesPage({super.key, this.repository});

  @override
  State<ImportBatchesPage> createState() => _ImportBatchesPageState();
}

class _ImportBatchesPageState extends State<ImportBatchesPage> {
  static const _pageSize = 20;

  final List<ImportBatch> _batches = [];
  ImportBatchStatusFilter _filter = ImportBatchStatusFilter.all;
  int _total = 0;
  int _offset = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  ImportExportRepository get _repository =>
      widget.repository ?? ImportExportRepository(context.read<ApiClient>());

  bool get _hasMore => _offset < _total;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
      _batches.clear();
      _total = 0;
      _offset = 0;
    });

    try {
      final page = await _repository.listBatches(
        status: _filter.value,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _batches.addAll(page.items);
        _total = page.total;
        _offset = page.nextOffset;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '加载导入批次失败：$error');
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
      final page = await _repository.listBatches(
        status: _filter.value,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _batches.addAll(page.items);
        _total = page.total;
        _offset = page.nextOffset;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '加载更多批次失败：$error');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _changeFilter(ImportBatchStatusFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _loadFirstPage();
  }

  void _openPreview(ImportBatch batch) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BillImportPreviewPage(
          batchId: batch.id,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入批次')),
      body: RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(total: _total, loaded: _batches.length),
            const SizedBox(height: 12),
            _FilterCard(selected: _filter, onSelected: _changeFilter),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!, onRetry: _loadFirstPage),
            ],
            const SizedBox(height: 12),
            if (_loading && _batches.isEmpty)
              const Center(child: CircularProgressIndicator())
            else
              _BatchListCard(batches: _batches, onOpenPreview: _openPreview),
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

class _HeaderCard extends StatelessWidget {
  final int total;
  final int loaded;

  const _HeaderCard({required this.total, required this.loaded});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.history_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '导入批次历史',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text('已加载 $loaded / $total 个批次'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  final ImportBatchStatusFilter selected;
  final ValueChanged<ImportBatchStatusFilter> onSelected;

  const _FilterCard({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ImportBatchStatusFilter.values
              .map((filter) {
                return FilterChip(
                  label: Text(filter.label),
                  selected: selected == filter,
                  onSelected: (_) => onSelected(filter),
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _BatchListCard extends StatelessWidget {
  final List<ImportBatch> batches;
  final ValueChanged<ImportBatch> onOpenPreview;

  const _BatchListCard({required this.batches, required this.onOpenPreview});

  @override
  Widget build(BuildContext context) {
    if (batches.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('暂无导入批次')),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('批次列表'),
            subtitle: Text('点击批次进入预览详情'),
          ),
          const Divider(height: 1),
          ...batches.map((batch) {
            return ListTile(
              leading: _StatusBadge(status: batch.status),
              title: Text(batch.filename ?? batch.id),
              subtitle: Text(
                '${_providerLabel(batch.sourceProvider)} · ${batch.validRows}/${batch.totalRows} 有效 · ${batch.createdAt ?? '-'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenPreview(batch),
            );
          }),
        ],
      ),
    );
  }

  String _providerLabel(String? provider) {
    return switch (provider) {
      'wechat' => '微信支付',
      'alipay' => '支付宝',
      'generic' => '通用 CSV',
      null || '' => '未知来源',
      _ => provider,
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
      'committed' => theme.colorScheme.primaryContainer,
      'rolled_back' => theme.colorScheme.errorContainer,
      _ => theme.colorScheme.secondaryContainer,
    };
    return Chip(label: Text(_statusLabel(status)), backgroundColor: color);
  }

  String _statusLabel(String status) {
    return switch (status) {
      'preview' => '预览',
      'committed' => '已提交',
      'rolled_back' => '已回滚',
      _ => status,
    };
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
    if (!hasMore) return const Center(child: Text('已加载全部批次'));
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
