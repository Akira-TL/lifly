import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showAiCaptureActionEditor(
  BuildContext context,
  AiCaptureAction action,
) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _AiCaptureActionEditorDialog(action: action),
  );
}

class _AiCaptureActionEditorDialog extends StatefulWidget {
  const _AiCaptureActionEditorDialog({required this.action});

  final AiCaptureAction action;

  @override
  State<_AiCaptureActionEditorDialog> createState() =>
      _AiCaptureActionEditorDialogState();
}

class _AiCaptureActionEditorDialogState
    extends State<_AiCaptureActionEditorDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final key in _editableKeys(widget.action.type))
        key: TextEditingController(text: _valueText(widget.action.payload[key])),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('修改${widget.action.label}'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in _controllers.entries) ...[
                TextField(
                  controller: entry.value,
                  minLines: _isLongField(entry.key) ? 2 : 1,
                  maxLines: _isLongField(entry.key) ? 5 : 1,
                  keyboardType: entry.key == 'amount'
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: _fieldLabel(entry.key),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存修改'),
        ),
      ],
    );
  }

  void _submit() {
    final payload = Map<String, dynamic>.from(widget.action.payload);
    for (final entry in _controllers.entries) {
      final value = entry.value.text.trim();
      if (entry.key == 'amount') {
        final amount = double.tryParse(value);
        if (amount == null || amount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('金额必须是大于 0 的数字。')),
          );
          return;
        }
        payload[entry.key] = amount;
      } else if (value.isEmpty) {
        payload[entry.key] = null;
      } else {
        payload[entry.key] = value;
      }
    }
    Navigator.of(context).pop(payload);
  }

  static List<String> _editableKeys(String type) {
    return switch (type) {
      'memo_create' => const ['title', 'content_markdown'],
      'task_create' => const [
        'title',
        'description',
        'remind_at',
        'priority',
      ],
      'expense_create' => const [
        'merchant',
        'amount',
        'note',
        'occurred_at',
      ],
      _ => const [],
    };
  }

  static bool _isLongField(String key) =>
      key == 'content_markdown' || key == 'description' || key == 'note';

  static String _fieldLabel(String key) {
    return switch (key) {
      'title' => '标题',
      'content_markdown' => '内容',
      'description' => '说明',
      'remind_at' => '提醒时间（ISO 8601）',
      'priority' => '优先级',
      'merchant' => '商户',
      'amount' => '金额',
      'note' => '备注',
      'occurred_at' => '发生时间（ISO 8601）',
      _ => key,
    };
  }

  static String _valueText(Object? value) => value?.toString() ?? '';
}
