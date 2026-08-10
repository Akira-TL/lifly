import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_capture_action_editor.dart';
import 'package:flutter/material.dart';

class AiCaptureTurnCard extends StatefulWidget {
  const AiCaptureTurnCard({
    super.key,
    required this.turn,
    required this.busy,
    required this.onCommit,
    required this.onRevise,
    required this.onUndo,
  });

  final AiCaptureTurn turn;
  final bool busy;
  final Future<void> Function(AiCaptureTurn turn, List<int> indexes) onCommit;
  final Future<void> Function(
    AiCaptureTurn turn,
    int actionIndex,
    Map<String, dynamic> payload,
  )
  onRevise;
  final Future<void> Function(AiCaptureTurn turn) onUndo;

  @override
  State<AiCaptureTurnCard> createState() => _AiCaptureTurnCardState();
}

class _AiCaptureTurnCardState extends State<AiCaptureTurnCard> {
  late Set<int> _selectedIndexes = _initialSelection(widget.turn);

  @override
  void didUpdateWidget(covariant AiCaptureTurnCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turn.id != widget.turn.id ||
        oldWidget.turn.turnStatus != widget.turn.turnStatus) {
      _selectedIndexes = _initialSelection(widget.turn);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.turn.role == 'user') return _buildUserTurn(context);
    if (widget.turn.role == 'assistant') return _buildAssistantTurn(context);
    return _buildSystemTurn(context);
  }

  Widget _buildUserTurn(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          color: colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.turn.text ?? ''),
                if (widget.turn.assetContext.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _AssetContextWrap(contexts: widget.turn.assetContext),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantTurn(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_outlined, size: 18),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _statusTitle(widget.turn.turnStatus),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                if (widget.turn.text?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(widget.turn.text!),
                ],
                if (widget.turn.assetContext.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _AssetContextWrap(contexts: widget.turn.assetContext),
                ],
                if (widget.turn.actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (
                    var index = 0;
                    index < widget.turn.actions.length;
                    index++
                  )
                    _ActionTile(
                      action: widget.turn.actions[index],
                      index: index,
                      selectable: widget.turn.canCommit,
                      selected: _selectedIndexes.contains(index),
                      canRevise: widget.turn.canRevise && !widget.busy,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedIndexes.add(index);
                          } else {
                            _selectedIndexes.remove(index);
                          }
                        });
                      },
                      onRevise: () => _revise(context, index),
                    ),
                ],
                if (widget.turn.resultEntities.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: widget.turn.resultEntities
                        .map(
                          (entity) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 17,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '已创建${_entityLabel(entity.type)}',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                if (widget.turn.canCommit || widget.turn.canUndo) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (widget.turn.canCommit)
                        FilledButton.icon(
                          onPressed: widget.busy || _selectedIndexes.isEmpty
                              ? null
                              : () => widget.onCommit(
                                  widget.turn,
                                  _selectedIndexes.toList()..sort(),
                                ),
                          icon: const Icon(Icons.check_outlined),
                          label: const Text('确认设置'),
                        ),
                      if (widget.turn.canUndo)
                        OutlinedButton.icon(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onUndo(widget.turn),
                          icon: const Icon(Icons.undo_outlined),
                          label: const Text('撤销'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemTurn(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          _systemLabel(widget.turn),
          style: Theme.of(context).textTheme.labelMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Future<void> _revise(BuildContext context, int index) async {
    final payload = await showAiCaptureActionEditor(
      context,
      widget.turn.actions[index],
    );
    if (payload == null || !mounted) return;
    await widget.onRevise(widget.turn, index, payload);
  }

  static Set<int> _initialSelection(AiCaptureTurn turn) {
    if (turn.selectedActionIndexes.isNotEmpty) {
      return turn.selectedActionIndexes.toSet();
    }
    return Set<int>.from(
      List<int>.generate(turn.actions.length, (index) => index),
    );
  }

  static String _statusTitle(String status) {
    return switch (status) {
      'parsed' => '建议设置',
      'revised' => '已更新建议',
      'superseded' => '旧版本',
      'committed' => '已完成',
      'partial' => '部分已完成',
      'failed' => '设置失败，可修改后重试',
      'undone' => '已撤销',
      _ => status,
    };
  }

  static String _systemLabel(AiCaptureTurn turn) {
    return switch (turn.turnStatus) {
      'undone' => '已撤销本轮 AI 设置',
      'dismissed' => '会话已关闭',
      _ => turn.text ?? turn.turnStatus,
    };
  }

  static String _entityLabel(String type) {
    return switch (type) {
      'memo' => '备忘',
      'task' => '任务',
      'ledger_transaction' => '账单',
      _ => type,
    };
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.index,
    required this.selectable,
    required this.selected,
    required this.canRevise,
    required this.onSelected,
    required this.onRevise,
  });

  final AiCaptureAction action;
  final int index;
  final bool selectable;
  final bool selected;
  final bool canRevise;
  final ValueChanged<bool> onSelected;
  final VoidCallback onRevise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: selectable
                ? Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    onChanged: (value) => onSelected(value ?? false),
                  )
                : Icon(_icon(action.type), size: 19),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '建议${action.label}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  action.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (canRevise)
            IconButton(
              tooltip: '修改',
              visualDensity: VisualDensity.compact,
              onPressed: onRevise,
              icon: const Icon(Icons.edit_outlined, size: 19),
            ),
        ],
      ),
    );
  }

  IconData _icon(String type) {
    return switch (type) {
      'memo_create' => Icons.note_add_outlined,
      'task_create' => Icons.add_task_outlined,
      'expense_create' => Icons.add_card_outlined,
      _ => Icons.auto_awesome_outlined,
    };
  }
}

class _AssetContextWrap extends StatelessWidget {
  const _AssetContextWrap({required this.contexts});

  final List<AiCaptureAssetContext> contexts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: contexts
          .map(
            (asset) => Tooltip(
              message: _tooltip(asset),
              child: Chip(
                avatar: Icon(_icon(asset), size: 17),
                label: Text(asset.displayName),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  String _tooltip(AiCaptureAssetContext asset) {
    final capability = asset.requiredCapability;
    return [
      asset.status,
      if (capability != null) '需要能力：$capability',
      if (asset.error != null) asset.error!,
    ].join('\n');
  }

  IconData _icon(AiCaptureAssetContext asset) {
    if (asset.status == 'ready') return Icons.check_circle_outline;
    if (asset.status == 'failed' || asset.status == 'missing') {
      return Icons.error_outline;
    }
    if (asset.status == 'unsupported') return Icons.hourglass_empty;
    return Icons.attach_file;
  }
}
