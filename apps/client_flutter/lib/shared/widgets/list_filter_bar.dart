import 'package:flutter/material.dart';

class ListFilterOption {
  final String label;
  final String? value;

  const ListFilterOption({required this.label, required this.value});
}

class ListFilterBar extends StatelessWidget {
  final List<ListFilterOption> options;
  final String? selectedValue;
  final ValueChanged<String?> onChanged;
  final EdgeInsetsGeometry padding;

  const ListFilterBar({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    Widget buildOption(ListFilterOption option) {
      final selected = selectedValue == option.value;
      if (wide) {
        return TextButton(
          onPressed: () => onChanged(option.value),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            foregroundColor: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
            backgroundColor: selected
                ? theme.colorScheme.surfaceContainerHigh
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Text(
            option.label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        );
      }

      return ChoiceChip(
        label: Text(option.label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onChanged(option.value),
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding,
          child: Row(
            children: [
              for (final option in options)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: buildOption(option),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
