import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/api/api_diagnostics.dart';
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
  String? _diagnosticError;
  bool _checkingHealth = false;
  bool _runningSmoke = false;

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
      setState(() => _diagnosticError = 'Health 检查失败：$error');
    } finally {
      if (mounted) {
        setState(() => _checkingHealth = false);
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
      setState(() => _diagnosticError = 'MCP smoke 检查失败：$error');
    } finally {
      if (mounted) {
        setState(() => _runningSmoke = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiClient>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          const _LocalMcpStatusCard(),
          const SizedBox(height: 12),
          const ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('同步状态'),
            subtitle: Text('未连接'),
          ),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('数据管理'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于 Lifly'),
            subtitle: Text('v0.1.0'),
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
        : '${health!.status} / v${health!.version}${health!.port == null ? '' : ' / :${health!.port}'}';
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
                Icon(Icons.api_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '后端连接诊断',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText('API Base URL: $baseUrl'),
            const SizedBox(height: 8),
            _StatusRow(label: 'Health', value: healthStatus),
            _StatusRow(label: 'MCP Smoke', value: smokeStatus),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (smokeReport != null) ...[
              const SizedBox(height: 8),
              ...smokeReport!.steps.map(
                (step) => _SmokeStepTile(step: step),
              ),
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
                  label: const Text('检查 Health'),
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
                  label: const Text('运行 MCP Smoke'),
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
  const _LocalMcpStatusCard();

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
                Icon(Icons.developer_board_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '本地能力 / Local MCP',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _StatusRow(label: '当前模式', value: 'Cloud API 直连'),
            const _StatusRow(label: 'Local Core', value: '已规划，未接入 Flutter'),
            const _StatusRow(label: 'Local MCP', value: 'stdio skeleton，未由客户端启动'),
            const _StatusRow(label: 'PowerSync', value: '未启用'),
            const _StatusRow(label: '离线写入', value: '未启用'),
            const SizedBox(height: 8),
            Text(
              '当前客户端仍通过后端 API 读写数据。本地 MCP / 离线写入会在 Local Core Bridge 与 PowerSync 接入后启用。',
              style: theme.textTheme.bodySmall,
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
    final color = step.passed ? Colors.green : Theme.of(context).colorScheme.error;
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
