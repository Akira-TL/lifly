import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/import_export_models.dart';
import 'package:client_flutter/data/repositories/import_export_repository.dart';
import 'package:client_flutter/features/import_export/data/bill_import_file_picker.dart';
import 'package:client_flutter/features/import_export/pages/bill_import_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BillImportPage extends StatefulWidget {
  final BillImportFilePicker filePicker;
  final ImportExportRepository? repository;

  const BillImportPage({
    super.key,
    this.filePicker = const FileSelectorBillImportFilePicker(),
    this.repository,
  });

  @override
  State<BillImportPage> createState() => _BillImportPageState();
}

class _BillImportPageState extends State<BillImportPage> {
  ImportProvider _provider = ImportProvider.auto;
  BillImportSelectedFile? _selectedFile;
  ImportUploadPreview? _preview;
  String? _error;
  bool _picking = false;
  bool _uploading = false;

  bool get _busy => _picking || _uploading;

  Future<void> _pickAndUpload() async {
    setState(() {
      _picking = true;
      _error = null;
    });

    BillImportSelectedFile? file;
    try {
      file = await widget.filePicker.pickBillFile();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '选择文件失败：$error');
      return;
    } finally {
      if (mounted) setState(() => _picking = false);
    }

    if (file == null || !mounted) return;
    setState(() {
      _selectedFile = file;
      _uploading = true;
      _preview = null;
      _error = null;
    });

    try {
      final repository =
          widget.repository ??
          ImportExportRepository(context.read<ApiClient>());
      final preview = await repository.uploadPreview(
        bytes: file.bytes,
        filename: file.name,
        provider: _provider,
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '上传预览失败：$error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataMode = context.watch<LiflyDataMode>();
    final apiMode = dataMode == LiflyDataMode.api;

    return Scaffold(
      appBar: AppBar(title: const Text('账单导入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _IntroCard(apiMode: apiMode),
          const SizedBox(height: 12),
          _ProviderCard(
            provider: _provider,
            enabled: apiMode && !_busy,
            onChanged: (provider) => setState(() => _provider = provider),
          ),
          const SizedBox(height: 12),
          _FileUploadCard(
            selectedFile: _selectedFile,
            picking: _picking,
            uploading: _uploading,
            enabled: apiMode && !_busy,
            onPick: _pickAndUpload,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorCard(message: _error!),
          ],
          if (_preview != null) ...[
            const SizedBox(height: 12),
            _PreviewSummaryCard(
              preview: _preview!,
              onOpenDetail: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BillImportPreviewPage(
                    batchId: _preview!.batchId,
                    repository: widget.repository,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final bool apiMode;

  const _IntroCard({required this.apiMode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_file, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '微信 / 支付宝流水导入',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('选择 CSV / XLSX 文件后会先上传预览，不会立即写入记账流水。'),
            const SizedBox(height: 8),
            Text(
              apiMode
                  ? '当前为云端模式，可上传并生成预览。'
                  : '当前为本地模式，导入预览需要连接云端服务。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: apiMode
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final ImportProvider provider;
  final bool enabled;
  final ValueChanged<ImportProvider> onChanged;

  const _ProviderCard({
    required this.provider,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<ImportProvider>(
          initialValue: provider,
          decoration: const InputDecoration(
            labelText: '账单来源',
            helperText: '选择自动识别时会判断微信 / 支付宝格式',
          ),
          items: ImportProvider.values
              .map(
                (provider) => DropdownMenuItem(
                  value: provider,
                  child: Text(_providerLabel(provider)),
                ),
              )
              .toList(growable: false),
          onChanged: enabled
              ? (provider) {
                  if (provider != null) onChanged(provider);
                }
              : null,
        ),
      ),
    );
  }

  String _providerLabel(ImportProvider provider) {
    return switch (provider) {
      ImportProvider.auto => '自动识别',
      ImportProvider.wechat => '微信支付',
      ImportProvider.alipay => '支付宝',
      ImportProvider.generic => '通用 CSV',
    };
  }
}

class _FileUploadCard extends StatelessWidget {
  final BillImportSelectedFile? selectedFile;
  final bool picking;
  final bool uploading;
  final bool enabled;
  final VoidCallback onPick;

  const _FileUploadCard({
    required this.selectedFile,
    required this.picking,
    required this.uploading,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonLabel = picking
        ? '选择中...'
        : uploading
        ? '上传预览中...'
        : '选择账单文件';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(selectedFile == null ? '尚未选择文件' : selectedFile!.name),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: enabled ? onPick : null,
              icon: picking || uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_open_outlined),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSummaryCard extends StatelessWidget {
  final ImportUploadPreview preview;
  final VoidCallback onOpenDetail;

  const _PreviewSummaryCard({
    required this.preview,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '预览已生成',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText('导入编号：${preview.batchId}'),
            Text('识别来源：${_sourceProviderLabel(preview.sourceProvider)}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(label: '总行数', value: preview.totalRows),
                _StatChip(label: '有效', value: preview.validRows),
                _StatChip(label: '重复', value: preview.duplicateRows),
                _StatChip(label: '错误', value: preview.errorRows),
                _StatChip(label: '忽略', value: preview.ignoredRows),
              ],
            ),
            if (preview.preview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '前 ${preview.preview.length} 行预览',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...preview.preview.take(5).map(_PreviewRowTile.new),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpenDetail,
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('查看完整预览'),
            ),
          ],
        ),
      ),
    );
  }
}

String _sourceProviderLabel(String sourceProvider) {
  return switch (sourceProvider) {
    'wechat' => '微信支付',
    'alipay' => '支付宝',
    'generic' => '通用账单',
    _ => '自动识别',
  };
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

class _PreviewRowTile extends StatelessWidget {
  final ImportPreviewRow row;

  const _PreviewRowTile(this.row);

  @override
  Widget build(BuildContext context) {
    final parsed = row.parsedData ?? const <String, dynamic>{};
    final merchant = parsed['merchant'] ?? parsed['description'] ?? '未解析商户';
    final amount = parsed['amount'] ?? '-';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Text('#${row.rowIndex}'),
      title: Text('$merchant · $amount'),
      subtitle: Text(row.errorMessage ?? row.status),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}
