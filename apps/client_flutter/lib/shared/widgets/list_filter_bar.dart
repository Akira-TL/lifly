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
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: options
              .map(
                (option) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(option.label),
                    selected: selectedValue == option.value,
                    onSelected: (_) => onChanged(option.value),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
