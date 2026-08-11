import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TaskDateTimeField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final Key pickerKey;
  final Key clearKey;

  const TaskDateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.pickerKey,
    required this.clearKey,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value?.toLocal() ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = value == null
        ? '未设置'
        : DateFormat('yyyy-MM-dd HH:mm').format(value!.toLocal());

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: TextButton(
              key: pickerKey,
              onPressed: () => _pick(context),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              child: Text(display),
            ),
          ),
          if (value != null)
            IconButton(
              key: clearKey,
              tooltip: '清除$label',
              onPressed: () => onChanged(null),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }
}
