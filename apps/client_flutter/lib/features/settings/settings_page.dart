import 'package:client_flutter/app/app_config.dart';
import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/api/api_diagnostics.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/powersync/powersync_connection_coordinator.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/sync_push_service.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:client_flutter/features/import_export/widgets/import_export_settings_section.dart';
import 'package:client_flutter/features/settings/widgets/account_device_settings_section.dart';
import 'package:client_flutter/features/settings/widgets/theme_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ApiHealthStatus? _health;
  McpSmokeReport? _smokeReport;
  AiAuditSummary? _aiAuditSummary;
  LocalCoreHealth? _localCoreHealth;
  LiflyPowerSyncCredentials? _powerSyncCredentials;
  SyncPushUploadDiagnostics _uploadDiagnostics =
      const SyncPushUploadDiagnostics.idle();
  PowerSyncConnectionDiagnostics _connectionDiagnostics =
      const PowerSyncConnectionDiagnostics.idle();
  String? _diagnosticError;
  String? _aiAuditError;
  String? _localCoreError;
  String? _powerSyncCredentialsError;
  bool _checkingHealth = false;
  bool _runningSmoke = false;
  bool _checkingAiAudit = false;
  bool _checkingLocalCore = false;
  bool _checkingPowerSyncCredentials = false;
  bool _connectingPowerSync = false;
  bool _disconnectingPowerSync = false;

  Future<void> _checkHealth() async {
    setState(() {
      _checkingHealth = true;
      _diagnosticError = null;
    });

    try {
      final diagnostics = ApiDiagnosticsService(context.read<ApiClient>());
      final health = await diagnostics.fetchHealth();
      if (!mounted) return;
      setState(() => _health = health);
    } catch (error) {
      if (!mounted) return;
      setState(() => _diagnosticError = '服务连接检查失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checkingHealth = false);
      }
    }
  }

  Future<void> _checkAiAudit() async {
    setState(() {
      _checkingAiAudit = true;
      _aiAuditError = null;
    });

    try {
      final diagnostics = ApiDiagnosticsService(context.read<ApiClient>());
      final summary = await diagnostics.fetchAiAuditSummary();
      if (!mounted) return;
      setState(() => _aiAuditSummary = summary);
    } catch (error) {
      if (!mounted) return;
      setState(() => _aiAuditError = 'AI 操作记录检查失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checkingAiAudit = false);
      }
    }
  }

  Future<void> _runMcpSmoke() async {
    setState(() {
      _runningSmoke = true;
      _diagnosticError = null;
    });

    try {
      final diagnostics = ApiDiagnosticsService(context.read<ApiClient>());
      final report = await diagnostics.runMcpSmoke();
      if (!mounted) return;
      setState(() => _smokeReport = report);
    } catch (error) {
      if (!mounted) return;
      setState(() => _diagnosticError = '完整检查失败：$error');
    } finally {
      if (mounted) {
        setState(() => _runningSmoke = false);
      }
    }
  }

  Future<void> _checkLocalCore() async {
    setState(() {
      _checkingLocalCore = true;
      _localCoreError = null;
    });

    try {
      final localCore = context.read<LocalCoreBridge>();
      final health = await localCore.health();
      if (!mounted) return;
      setState(() {
        _localCoreHealth = health;
        _localCoreError = health.healthy ? null : health.detail;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _localCoreError = '本地能力检查失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checkingLocalCore = false);
      }
    }
  }

  Future<void> _checkPowerSyncCredentials() async {
    setState(() {
      _checkingPowerSyncCredentials = true;
      _powerSyncCredentialsError = null;
    });

    try {
      final service = PowerSyncCredentialsService(context.read<ApiClient>());
      final syncService = context.read<SyncService>();
      final coordinator = context.read<PowerSyncConnectionCoordinator>();
      final credentials = await service.fetchCredentials();
      final uploadDiagnostics = syncService.uploadDiagnostics;
      final connectionDiagnostics = coordinator.refreshDiagnostics();
      if (!mounted) return;
      setState(() {
        _powerSyncCredentials = credentials;
        _uploadDiagnostics = uploadDiagnostics;
        _connectionDiagnostics = connectionDiagnostics;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _powerSyncCredentialsError = '同步凭据检查失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checkingPowerSyncCredentials = false);
      }
    }
  }

  Future<void> _connectPowerSync() async {
    setState(() {
      _connectingPowerSync = true;
      _powerSyncCredentialsError = null;
    });

    try {
      final coordinator = context.read<PowerSyncConnectionCoordinator>();
      final diagnostics = await coordinator.connect();
      if (!mounted) return;
      setState(() {
        _connectionDiagnostics = diagnostics;
        _powerSyncCredentials = diagnostics.credentials;
        _uploadDiagnostics = diagnostics.uploadDiagnostics;
        _powerSyncCredentialsError = diagnostics.error == null
            ? null
            : '数据同步连接失败：${diagnostics.error}';
      });
    } finally {
      if (mounted) {
        setState(() => _connectingPowerSync = false);
      }
    }
  }

  Future<void> _disconnectPowerSync() async {
    setState(() {
      _disconnectingPowerSync = true;
      _powerSyncCredentialsError = null;
    });

    try {
      final coordinator = context.read<PowerSyncConnectionCoordinator>();
      final diagnostics = await coordinator.disconnect();
      if (!mounted) return;
      setState(() {
        _connectionDiagnostics = diagnostics;
        _uploadDiagnostics = diagnostics.uploadDiagnostics;
        _powerSyncCredentialsError = diagnostics.error == null
            ? null
            : '数据同步断开失败：${diagnostics.error}';
      });
    } finally {
      if (mounted) {
        setState(() => _disconnectingPowerSync = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiClient>();
    final dataMode = context.watch<LiflyDataMode>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ThemeSettingsSection(),
          const SizedBox(height: 12),
          AccountDeviceSettingsSection(api: api),
          const SizedBox(height: 12),
          _ApiDiagnosticsCard(
            baseUrl: api.baseUrl,
            health: _health,
            smokeReport: _smokeReport,
            error: _diagnosticError,
            checkingHealth: _checkingHealth,
            runningSmoke: _runningSmoke,
            onCheckHealth: _checkHealth,
            onRunMcpSmoke: _runMcpSmoke,
          ),
          const SizedBox(height: 12),
          _DataModeCard(dataMode: dataMode),
          const SizedBox(height: 12),
          _AiAuditSummaryCard(
            summary: _aiAuditSummary,
            error: _aiAuditError,
            checking: _checkingAiAudit,
            onCheck: _checkAiAudit,
          ),
          const SizedBox(height: 12),
          _LocalMcpStatusCard(
            health: _localCoreHealth,
            error: _localCoreError,
            checking: _checkingLocalCore,
            onCheck: _checkLocalCore,
          ),
          const SizedBox(height: 12),
          _PowerSyncCredentialsCard(
            credentials: _powerSyncCredentials,
            connectionDiagnostics: _connectionDiagnostics,
            uploadDiagnostics: _uploadDiagnostics,
            error: _powerSyncCredentialsError,
            checking: _checkingPowerSyncCredentials,
            connecting: _connectingPowerSync,
            disconnecting: _disconnectingPowerSync,
            onCheck: _checkPowerSyncCredentials,
            onConnect: _connectPowerSync,
            onDisconnect: _disconnectPowerSync,
          ),
          const SizedBox(height: 12),
          ImportExportSettingsSection(dataMode: dataMode),
          const SizedBox(height: 12),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于 Lifly'),
            subtitle: Text('v${AppConfig.appVersion}'),
          ),
        ],
      ),
    );
  }
}

class _ApiDiagnosticsCard extends StatelessWidget {
  final String baseUrl;
  final ApiHealthStatus? health;
  final McpSmokeReport? smokeReport;
  final String? error;
  final bool checkingHealth;
  final bool runningSmoke;
  final VoidCallback onCheckHealth;
  final VoidCallback onRunMcpSmoke;

  const _ApiDiagnosticsCard({
    required this.baseUrl,
    required this.health,
    required this.smokeReport,
    required this.error,
    required this.checkingHealth,
    required this.runningSmoke,
    required this.onCheckHealth,
    required this.onRunMcpSmoke,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final healthStatus = health == null
        ? '未检查'
        : health!.status == 'ok'
        ? '正常'
        : health!.status;
    final smokeStatus = smokeReport == null
        ? '未运行'
        : '${smokeReport!.passedCount}/${smokeReport!.totalCount} ${smokeReport!.passed ? '通过' : '失败'}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '服务连接',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText('服务地址：$baseUrl'),
            const SizedBox(height: 8),
            _StatusRow(label: '连接状态', value: healthStatus),
            _StatusRow(label: '完整检查', value: smokeStatus),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (smokeReport != null) ...[
              const SizedBox(height: 8),
              ...smokeReport!.steps.map((step) => _SmokeStepTile(step: step)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: checkingHealth ? null : onCheckHealth,
                  icon: checkingHealth
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.monitor_heart_outlined),
                  label: const Text('检查连接'),
                ),
                OutlinedButton.icon(
                  onPressed: runningSmoke ? null : onRunMcpSmoke,
                  icon: runningSmoke
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_circle_outline),
                  label: const Text('运行完整检查'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DataModeCard extends StatelessWidget {
  final LiflyDataMode dataMode;

  const _DataModeCard({required this.dataMode});

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
                Icon(Icons.sync_alt_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '数据模式',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRow(label: '当前模式', value: dataMode.label),
            const _StatusRow(
              label: '本地可用',
              value: '备忘、任务、记账与 AI 对话',
            ),
            const _StatusRow(
              label: '云端能力',
              value: '跨端同步、导入与导出',
            ),
          ],
        ),
      ),
    );
  }
}

class _AiAuditSummaryCard extends StatelessWidget {
  final AiAuditSummary? summary;
  final String? error;
  final bool checking;
  final VoidCallback onCheck;

  const _AiAuditSummaryCard({
    required this.summary,
    required this.error,
    required this.checking,
    required this.onCheck,
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
                  Icons.verified_user_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 操作记录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRow(label: '操作总数', value: '${summary?.total ?? 0}'),
            if (summary != null && summary!.items.isNotEmpty)
              ...summary!.items.map(
                (item) => _StatusRow(
                  label: _aiAuditSourceLabel(item.sourceChannel),
                  value: '${item.count}',
                ),
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            Text(
              '这里只展示聚合数量，不展示用户输入的原始内容。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: checking ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_outlined),
              label: const Text('刷新记录'),
            ),
          ],
        ),
      ),
    );
  }
}

String _aiAuditSourceLabel(String sourceChannel) {
  return switch (sourceChannel) {
    'flutter' => '应用内',
    'local_mcp' || 'localMcp' => '本地 AI',
    'cloud_mcp' || 'cloudMcp' => '云端 AI',
    'import' => '导入',
    'system' => '系统',
    _ => '其他',
  };
}

class _PowerSyncCredentialsCard extends StatelessWidget {
  final LiflyPowerSyncCredentials? credentials;
  final PowerSyncConnectionDiagnostics connectionDiagnostics;
  final SyncPushUploadDiagnostics uploadDiagnostics;
  final String? error;
  final bool checking;
  final bool connecting;
  final bool disconnecting;
  final VoidCallback onCheck;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _PowerSyncCredentialsCard({
    required this.credentials,
    required this.connectionDiagnostics,
    required this.uploadDiagnostics,
    required this.error,
    required this.checking,
    required this.connecting,
    required this.disconnecting,
    required this.onCheck,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiresAt = credentials?.expiresAt.toLocal().toIso8601String();
    final connectedAt = connectionDiagnostics.connectedAt
        ?.toLocal()
        .toIso8601String();
    final disconnectedAt = connectionDiagnostics.disconnectedAt
        ?.toLocal()
        .toIso8601String();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_sync_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '数据同步',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRow(
              label: '服务地址',
              value: credentials?.endpoint ?? '未检查',
            ),
            _StatusRow(label: '账户', value: credentials?.userId ?? '未检查'),
            _StatusRow(
              label: '授权状态',
              value: credentials?.tokenStatus ?? '未获取',
            ),
            if (expiresAt != null)
              _StatusRow(label: '授权有效期', value: expiresAt),
            _StatusRow(label: '连接状态', value: connectionDiagnostics.statusLabel),
            if (connectedAt != null)
              _StatusRow(label: '连接时间', value: connectedAt),
            if (disconnectedAt != null)
              _StatusRow(label: '断开时间', value: disconnectedAt),
            _StatusRow(label: '上传状态', value: uploadDiagnostics.statusLabel),
            _StatusRow(
              label: '上传变更',
              value:
                  '${uploadDiagnostics.uploadedChanges} 条业务 / ${uploadDiagnostics.ignoredChanges} 条忽略',
            ),
            _StatusRow(
              label: '云端处理',
              value:
                  '已应用 ${uploadDiagnostics.applied} 条 / 已跳过 ${uploadDiagnostics.skipped} 条',
            ),
            if (uploadDiagnostics.lastError != null)
              _StatusRow(label: '同步错误', value: uploadDiagnostics.lastError!),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            Text(
              '连接后会自动同步本地变更；授权信息只显示状态，不展示密钥内容。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: connecting ? null : onConnect,
                  icon: connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  label: const Text('连接同步'),
                ),
                OutlinedButton.icon(
                  onPressed: checking ? null : onCheck,
                  icon: checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined),
                  label: const Text('刷新状态'),
                ),
                OutlinedButton.icon(
                  onPressed: disconnecting ? null : onDisconnect,
                  icon: disconnecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_off_outlined),
                  label: const Text('断开同步'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalMcpStatusCard extends StatelessWidget {
  final LocalCoreHealth? health;
  final String? error;
  final bool checking;
  final VoidCallback onCheck;

  const _LocalMcpStatusCard({
    required this.health,
    required this.error,
    required this.checking,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localCoreStatus = health == null
        ? '未检查'
        : health!.healthy
        ? '正常'
        : '异常';
    final checkedAt = health?.checkedAt?.toLocal().toIso8601String();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.offline_bolt_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '本地能力',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRow(label: '运行状态', value: localCoreStatus),
            const _StatusRow(
              label: '离线可用',
              value: '备忘、任务、记账与 AI 对话',
            ),
            const _StatusRow(
              label: '恢复联网',
              value: '连接后继续同步本地变更',
            ),
            if (checkedAt != null) _StatusRow(label: '检查时间', value: checkedAt),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            Text(
              '本地模式下可在断网时继续记录，恢复连接后再同步。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: checking ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.storage_outlined),
              label: const Text('检查本地能力'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _SmokeStepTile extends StatelessWidget {
  final McpSmokeStepResult step;

  const _SmokeStepTile({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = step.passed
        ? Colors.green
        : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            step.passed ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.detail == null ? step.name : '${step.name}: ${step.detail}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
