import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/features/import_export/pages/bill_import_page.dart';
import 'package:client_flutter/features/import_export/pages/export_page.dart';
import 'package:client_flutter/features/import_export/pages/import_batches_page.dart';
import 'package:flutter/material.dart';

class ImportExportSettingsSection extends StatelessWidget {
  final LiflyDataMode dataMode;

  const ImportExportSettingsSection({super.key, required this.dataMode});

  bool get _apiMode => dataMode == LiflyDataMode.api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('数据管理'),
            subtitle: Text(
              _apiMode
                  ? '云端模式：可导入、提交、追踪批次并导出数据'
                  : '本地模式：导入导出需要连接云端服务',
            ),
            trailing: Icon(
              _apiMode ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              color: _apiMode
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
          const Divider(height: 1),
          _DataActionTile(
            icon: Icons.upload_file_outlined,
            title: '账单导入',
            subtitle: '上传微信 / 支付宝流水，先生成预览，不会立即写入',
            enabled: _apiMode,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BillImportPage())),
          ),
          const Divider(height: 1),
          _DataActionTile(
            icon: Icons.fact_check_outlined,
            title: '导入批次',
            subtitle: '查看历史导入、继续检查预览或追踪提交结果',
            enabled: _apiMode,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportBatchesPage()),
            ),
          ),
          const Divider(height: 1),
          _DataActionTile(
            icon: Icons.download_outlined,
            title: '数据导出',
            subtitle: '生成导出预览，确认大小和校验值后下载文件',
            enabled: _apiMode,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ExportPage())),
          ),
        ],
      ),
    );
  }
}

class _DataActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _DataActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(enabled ? Icons.chevron_right : Icons.lock_outline),
      onTap: enabled ? onTap : null,
    );
  }
}
