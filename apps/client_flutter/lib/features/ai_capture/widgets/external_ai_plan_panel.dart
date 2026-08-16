import 'package:client_flutter/features/ai_capture/data/ai_capture_execution_runtime.dart';
import 'package:client_flutter/features/ai_capture/data/external_ai_action_committer.dart';
import 'package:client_flutter/features/ai_capture/models/cloud_ai_models.dart';
import 'package:flutter/material.dart';

class ExternalAiPlanPanel extends StatelessWidget {
  const ExternalAiPlanPanel({
    super.key,
    required this.plan,
    required this.commits,
    required this.busyIndexes,
    required this.undoneIndexes,
    required this.onCommit,
    required this.onUndo,
    required this.onClose,
  });

  final ExternalAiPlanResult plan;
  final Map<int, ExternalAiActionCommitResult> commits;
  final Set<int> busyIndexes;
  final Set<int> undoneIndexes;
  final ValueChanged<int> onCommit;
  final ValueChanged<int> onUndo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plan.sourceLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: '关闭执行结果',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Text(
              'AI 已默认执行可用操作；如需取消，可在下方点击“撤回”。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (plan.actions.isEmpty)
              const Text('AI 没有返回可执行候选动作。')
            else
              ...List.generate(plan.actions.length, (index) {
                final action = plan.actions[index];
                final capture = action.toCaptureAction();
                final committed = commits[index];
                final busy = busyIndexes.contains(index);
                final undone = undoneIndexes.contains(index);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      title: Text(capture.label),
                      subtitle: Text(capture.summary),
                      trailing: undone
                          ? const Text('已撤回')
                          : committed != null
                          ? OutlinedButton(
                              onPressed: busy ? null : () => onUndo(index),
                              child: Text(busy ? '撤回中' : '撤回'),
                            )
                          : FilledButton.tonal(
                              onPressed: busy ? null : () => onCommit(index),
                              child: Text(busy ? '处理中' : '重试'),
                            ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
