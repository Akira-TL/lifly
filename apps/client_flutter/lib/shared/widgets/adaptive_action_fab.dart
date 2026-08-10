import 'package:flutter/material.dart';

/// Keeps primary create actions compact on phone-sized layouts while
/// preserving descriptive extended FABs on wider workspaces.
class AdaptiveActionFab extends StatelessWidget {
  const AdaptiveActionFab({
    super.key,
    required this.heroTag,
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  final Object heroTag;
  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final iconWidget = isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);

    if (compact) {
      return FloatingActionButton(
        heroTag: heroTag,
        tooltip: tooltip,
        onPressed: onPressed,
        child: iconWidget,
      );
    }

    return FloatingActionButton.extended(
      heroTag: heroTag,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: iconWidget,
      label: Text(label),
    );
  }
}
