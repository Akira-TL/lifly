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
  ) onRevise;
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
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_outlined, size: 20),
                    const SizedBox(width: 8),
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
                  const SizedBox(height: 8),
                  for (var index = 0;
                      index < widget.turn.actions.length;
                      index++)
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
                  const Divider(),
                  Text(
                    '已设置内容',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.turn.resultEntities
                        .map(
                          (entity) => Chip(
                            avatar: Icon(_entityIcon(entity.type), size: 18),
                            label: Text('${_entityLabel(entity.type)} · ${entity.id}'),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                if (widget.turn.canCommit || widget.turn.canUndo) ...[
                  const SizedBox(height: 10),
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
      'parsed' => 'AI 已整理候选内容',
      'revised' => '已按修改生成新版本',
      'superseded' => '旧版本（已被修改）',
      'committed' => 'AI 已完成设置',
      'partial' => '部分内容已设置',
      'failed' => '设置失败，可修改后重试',
      'undone' => '本轮设置已撤销',
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

  static IconData _entityIcon(String type) {
    return switch (type) {
      'memo' => Icons.note_outlined,
      'task' => Icons.check_circle_outline,
      'ledger_transaction' => Icons.account_balance_wallet_outlined,
      _ => Icons.data_object_outlined,
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: selectable
          ? Checkbox(
              value: selected,
              onChanged: (value) => onSelected(value ?? false),
            )
          : Icon(_icon(action.type)),
      title: Text('${action.label} · ${action.summary}'),
      subtitle: Text('置信度 ${action.confidence.toStringAsFixed(2)}'),
      trailing: canRevise
          ? IconButton(
              tooltip: '修改',
              onPressed: onRevise,
              icon: const Icon(Icons.edit_outlined),
            )
          : null,
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
