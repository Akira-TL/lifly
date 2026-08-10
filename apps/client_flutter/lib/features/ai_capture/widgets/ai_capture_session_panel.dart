import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AiCaptureSessionPanel extends StatelessWidget {
  const AiCaptureSessionPanel({
    super.key,
    required this.sessions,
    required this.selectedCaptureId,
    required this.onSelected,
    required this.onNew,
  });

  final List<AiCaptureSession> sessions;
  final String? selectedCaptureId;
  final ValueChanged<String> onSelected;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: onNew,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.add_comment_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '新会话',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: sessions.isEmpty
              ? Center(
                  child: Text(
                    '暂无历史会话',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return _SessionRow(
                      session: session,
                      selected: session.captureId == selectedCaptureId,
                      onTap: () => onSelected(session.captureId),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final AiCaptureSession session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = session.originalText.trim().isEmpty
        ? '未命名会话'
        : session.originalText.trim();
    final metadata = [
      '${session.turnCount} 条',
      if (session.updatedAt != null)
        DateFormat('MM/dd HH:mm').format(session.updatedAt!.toLocal()),
    ].join(' · ');

    return Material(
      color: selected
          ? theme.colorScheme.surfaceContainerHigh
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Row(
            children: [
              SizedBox(
                width: 3,
                height: 34,
                child: ColoredBox(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
