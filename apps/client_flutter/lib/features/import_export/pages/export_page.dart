import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/import_export_models.dart';
import 'package:client_flutter/data/repositories/import_export_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ExportPage extends StatefulWidget {
  final ImportExportRepository? repository;

  const ExportPage({super.key, this.repository});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  ExportEntityType _entityType = ExportEntityType.all;
  ExportMetadata? _metadata;
  ExportStreamPayload? _download;
  String? _error;
  bool _loadingMetadata = false;
  bool _downloading = false;

  bool get _busy => _loadingMetadata || _downloading;

  ImportExportRepository get _repository =>
      widget.repository ?? ImportExportRepository(context.read<ApiClient>());

  Future<void> _loadMetadata() async {
    setState(() {
      _loadingMetadata = true;
      _error = null;
      _metadata = null;
      _download = null;
    });

    try {
      final metadata = await _repository.exportMetadata(
        entityType: _entityType,
      );
      if (!mounted) return;
      setState(() => _metadata = metadata);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '生成导出预览失败：$error');
    } finally {
      if (mounted) setState(() => _loadingMetadata = false);
    }
  }

  Future<void> _downloadExport() async {
    setState(() {
      _downloading = true;
      _error = null;
      _download = null;
    });

    try {
      final payload = await _repository.downloadExport(entityType: _entityType);
      if (!mounted) return;
      setState(() => _download = payload);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '下载导出文件失败：$error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _changeEntityType(ExportEntityType entityType) {
    setState(() {
      _entityType = entityType;
      _metadata = null;
      _download = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dataMode = context.watch<LiflyDataMode>();
    final apiMode = dataMode == LiflyDataMode.api;

    return Scaffold(
      appBar: AppBar(title: const Text('数据导出')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _IntroCard(apiMode: apiMode),
          const SizedBox(height: 12),
          _ExportSelectorCard(
            entityType: _entityType,
            enabled: apiMode && !_busy,
            onChanged: _changeEntityType,
          ),
          const SizedBox(height: 12),
          _ExportActionCard(
            apiMode: apiMode,
            loadingMetadata: _loadingMetadata,
            downloading: _downloading,
            onLoadMetadata: _loadMetadata,
            onDownload: _downloadExport,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorCard(message: _error!),
          ],
          if (_metadata != null) ...[
            const SizedBox(height: 12),
            _MetadataCard(metadata: _metadata!),
          ],
          if (_download != null) ...[
            const SizedBox(height: 12),
            _DownloadResultCard(payload: _download!),
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
                Icon(Icons.download_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Lifly 数据导出',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('先生成导出元数据预览，确认文件名、大小和校验值后再下载导出流。'),
            const SizedBox(height: 8),
            Text(
              apiMode
                  ? '当前为云端模式，可生成和下载导出。'
                  : '当前为本地模式，导出需要连接云端服务。',
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

class _ExportSelectorCard extends StatelessWidget {
  final ExportEntityType entityType;
  final bool enabled;
  final ValueChanged<ExportEntityType> onChanged;

  const _ExportSelectorCard({
    required this.entityType,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<ExportEntityType>(
          initialValue: entityType,
          decoration: const InputDecoration(
            labelText: '导出范围',
            helperText: '记账流水会包含在导出数据中',
          ),
          items: ExportEntityType.values
              .map((entityType) {
                return DropdownMenuItem(
                  value: entityType,
                  child: Text(_entityTypeLabel(entityType)),
                );
              })
              .toList(growable: false),
          onChanged: enabled
              ? (entityType) {
                  if (entityType != null) onChanged(entityType);
                }
              : null,
        ),
      ),
    );
  }

  String _entityTypeLabel(ExportEntityType entityType) {
    return switch (entityType) {
      ExportEntityType.all => '全部数据',
      ExportEntityType.ledgerTransactions => '记账流水',
      ExportEntityType.memos => '备忘',
      ExportEntityType.tasks => '任务',
      ExportEntityType.assets => '附件',
    };
  }
}

class _ExportActionCard extends StatelessWidget {
  final bool apiMode;
  final bool loadingMetadata;
  final bool downloading;
  final VoidCallback onLoadMetadata;
  final VoidCallback onDownload;

  const _ExportActionCard({
    required this.apiMode,
    required this.loadingMetadata,
    required this.downloading,
    required this.onLoadMetadata,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final busy = loadingMetadata || downloading;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: apiMode && !busy ? onLoadMetadata : null,
              icon: loadingMetadata
                  ? const _SmallProgress()
                  : const Icon(Icons.fact_check_outlined),
              label: Text(loadingMetadata ? '生成中...' : '生成导出预览'),
            ),
            OutlinedButton.icon(
              onPressed: apiMode && !busy ? onDownload : null,
              icon: downloading
                  ? const _SmallProgress()
                  : const Icon(Icons.download_for_offline_outlined),
              label: Text(downloading ? '下载中...' : '下载导出文件'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final ExportMetadata metadata;

  const _MetadataCard({required this.metadata});

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
                  Icons.description_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '导出预览',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailLine(label: '文件名', value: metadata.filename),
            _DetailLine(label: '实体类型', value: metadata.entityType),
            _DetailLine(label: '格式', value: metadata.format),
            _DetailLine(label: 'Media Type', value: metadata.mediaType),
            _DetailLine(label: '大小', value: '${metadata.sizeBytes} bytes'),
            _DetailLine(label: 'Checksum', value: metadata.checksumSha256),
            _DetailLine(label: 'Contract', value: metadata.contractVersion),
            if (metadata.counts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: metadata.counts.entries
                    .map((entry) {
                      return Chip(label: Text('${entry.key}：${entry.value}'));
                    })
                    .toList(growable: false),
              ),
            ],
            if (metadata.preview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('内容预览', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(metadata.preview),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadResultCard extends StatelessWidget {
  final ExportStreamPayload payload;

  const _DownloadResultCard({required this.payload});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = payload.metadata;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '下载完成',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailLine(label: '下载字节数', value: '${payload.bytes.length} bytes'),
            _DetailLine(label: '文件名', value: metadata.filename ?? '-'),
            _DetailLine(label: '实体类型', value: metadata.entityType),
            _DetailLine(label: 'Media Type', value: metadata.mediaType ?? '-'),
            _DetailLine(
              label: 'Header Size',
              value: metadata.sizeBytes?.toString() ?? '-',
            ),
            _DetailLine(
              label: 'Checksum',
              value: metadata.checksumSha256 ?? '-',
            ),
            _DetailLine(
              label: 'Contract',
              value: metadata.contractVersion ?? '-',
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SelectableText('$label：$value'),
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

class _SmallProgress extends StatelessWidget {
  const _SmallProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
