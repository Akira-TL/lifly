import 'package:flutter/material.dart';

/// A flat, scan-first list row for high-density Lifly content pages.
///
/// Hierarchy comes from typography, a small semantic accent, and separators
/// supplied by the parent list instead of a card around every record.
class DenseListRow extends StatelessWidget {
  final VoidCallback onTap;
  final Widget title;
  final Widget? subtitle;
  final Widget? metadata;
  final Widget? trailing;
  final Color? accentColor;
  final double minHeight;
  final EdgeInsetsGeometry padding;

  const DenseListRow({
    super.key,
    required this.onTap,
    required this.title,
    this.subtitle,
    this.metadata,
    this.trailing,
    this.accentColor,
    this.minHeight = 64,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (accentColor != null) ...[
                  Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle.merge(
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        child: title,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle.merge(
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          child: subtitle!,
                        ),
                      ],
                      if (metadata != null) ...[
                        const SizedBox(height: 3),
                        DefaultTextStyle.merge(
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          child: metadata!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
