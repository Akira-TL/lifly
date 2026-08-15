import 'package:client_flutter/data/device/device_contracts.dart';
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
  });

  final AiExecutionTarget target;
  final List<DeviceDescriptor> computeNodes;
  final String? selectedComputeNodeId;
  final String computeStatusText;
  final ValueChanged<AiExecutionTarget> onTargetChanged;
  final ValueChanged<String?> onComputeNodeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<AiExecutionTarget>(
                segments: const [
                  ButtonSegment(
                    value: AiExecutionTarget.existing,
                    label: Text('当前处理'),
                    icon: Icon(Icons.auto_awesome_outlined),
                  ),
                  ButtonSegment(
                    value: AiExecutionTarget.computeNode,
                    label: Text('我的电脑'),
                    icon: Icon(Icons.computer_outlined),
                  ),
                  ButtonSegment(
                    value: AiExecutionTarget.cloudAi,
                    label: Text('Cloud AI'),
                    icon: Icon(Icons.cloud_outlined),
                  ),
                ],
                selected: {target},
                showSelectedIcon: false,
                onSelectionChanged: (values) {
                  if (values.isNotEmpty) onTargetChanged(values.first);
                },
              ),
            ),
            if (target == AiExecutionTarget.computeNode) ...[
              const SizedBox(height: 8),
              if (computeNodes.isEmpty)
                const Text('没有可执行 local_ai 的 Trusted Compute Node。')
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
                'Cloud AI 只会在你每次明确确认后收到本次允许披露的数据。',
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
