import 'package:client_flutter/features/asset/pages/asset_list_page.dart';
import 'package:client_flutter/features/import_export/pages/bill_import_page.dart';
import 'package:client_flutter/features/import_export/pages/export_page.dart';
import 'package:client_flutter/features/import_export/pages/import_batches_page.dart';
import 'package:client_flutter/features/settings/settings_page.dart';
import 'package:flutter/material.dart';

class ManagementHubPage extends StatelessWidget {
  const ManagementHubPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理中心')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              const _ManagementIntroduction(),
              const SizedBox(height: 24),
              _ManagementSection(
                title: '数据流转',
                subtitle: '导入外部流水、查看处理批次并导出 Lifly 数据。',
                entries: [
                  _ManagementEntry(
                    key: const Key('management_bill_import'),
                    icon: Icons.upload_file_outlined,
                    title: '账单导入',
                    subtitle: '导入支付宝、微信或通用 CSV 流水',
                    onTap: () => _open(context, const BillImportPage()),
                  ),
                  _ManagementEntry(
                    key: const Key('management_import_batches'),
                    icon: Icons.inventory_2_outlined,
                    title: '导入批次',
                    subtitle: '查看预览、提交状态和批次回滚记录',
                    onTap: () => _open(context, const ImportBatchesPage()),
                  ),
                  _ManagementEntry(
                    key: const Key('management_export'),
                    icon: Icons.download_outlined,
                    title: '数据导出',
                    subtitle: '导出 Markdown、CSV 或 JSON 数据',
                    onTap: () => _open(context, const ExportPage()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _ManagementSection(
                title: '数据资产',
                subtitle: '管理正文之外的文件、图片和外部链接。',
                entries: [
                  _ManagementEntry(
                    key: const Key('management_assets'),
                    icon: Icons.attach_file_outlined,
                    title: '附件库',
                    subtitle: '上传文件、登记外链并查看同步状态',
                    onTap: () => _open(context, const AssetListPage()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _ManagementSection(
                title: '系统与诊断',
                subtitle: '调整外观，并检查数据连接、本地能力与同步状态。',
                entries: [
                  _ManagementEntry(
                    key: const Key('management_settings'),
                    icon: Icons.settings_outlined,
                    title: '设置与诊断',
                    subtitle: '主题、数据模式、同步连接和运行诊断',
                    onTap: () => _open(context, const SettingsPage()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagementIntroduction extends StatelessWidget {
  const _ManagementIntroduction();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.dashboard_customize_outlined,
              color: theme.colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '全局数据与系统工具',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '核心导航只保留首页、备忘、AI、记账和任务；低频管理能力统一从这里进入。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_ManagementEntry> entries;

  const _ManagementSection({
    required this.title,
    required this.subtitle,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 2 : 1;
            final spacing = 12.0;
            final itemWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: entries
                  .map((entry) => SizedBox(width: itemWidth, child: entry))
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _ManagementEntry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ManagementEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 88,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
