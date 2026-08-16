import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AiExecutionTarget { existing, computeNode, cloudAi }

class AiExecutionTargetBar extends StatelessWidget {
  const AiExecutionTargetBar({
    super.key,
    required this.target,
    required this.computeNodes,
    required this.selectedComputeNodeId,
    required this.computeStatusText,
    required this.onTargetChanged,
    required this.onComputeNodeChanged,
    this.webMode,
  });

  final AiExecutionTarget target;
  final List<DeviceDescriptor> computeNodes;
  final String? selectedComputeNodeId;
  final String computeStatusText;
  final ValueChanged<AiExecutionTarget> onTargetChanged;
  final ValueChanged<String?> onComputeNodeChanged;
  final bool? webMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWeb = webMode ?? kIsWeb;
    final targets = <({AiExecutionTarget value, String label, IconData icon})>[
      if (!isWeb)
        (
          value: AiExecutionTarget.existing,
          label: '当前处理',
          icon: Icons.auto_awesome_outlined,
        ),
      (
        value: AiExecutionTarget.computeNode,
        label: '我的电脑',
        icon: Icons.computer_outlined,
      ),
      (
        value: AiExecutionTarget.cloudAi,
        label: '云端 AI',
        icon: Icons.cloud_outlined,
      ),
    ];
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in targets)
                  ChoiceChip(
                    selected: target == item.value,
                    showCheckmark: false,
                    avatar: Icon(item.icon, size: 18),
                    label: Text(item.label, maxLines: 1),
                    onSelected: (_) => onTargetChanged(item.value),
                  ),
              ],
            ),
            if (target == AiExecutionTarget.computeNode) ...[
              const SizedBox(height: 8),
              if (computeNodes.isEmpty)
                const Text('没有可用的可信本地计算节点。')
              else
                DropdownButtonFormField<String>(
                  key: const Key('ai_compute_node_selector'),
                  initialValue:
                      computeNodes.any(
                        (device) => device.deviceId == selectedComputeNodeId,
                      )
                      ? selectedComputeNodeId
                      : null,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: '执行设备',
                    border: OutlineInputBorder(),
                  ),
                  items: computeNodes
                      .map(
                        (device) => DropdownMenuItem(
                          value: device.deviceId,
                          child: Text(
                            device.isDefaultComputeNode
                                ? '${device.displayName} · 默认'
                                : device.displayName,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: onComputeNodeChanged,
                ),
              const SizedBox(height: 6),
              Text(
                computeStatusText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (target == AiExecutionTarget.cloudAi) ...[
              const SizedBox(height: 6),
              Text(
                '云端 AI 只会在你每次明确确认后收到本次允许披露的数据。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
