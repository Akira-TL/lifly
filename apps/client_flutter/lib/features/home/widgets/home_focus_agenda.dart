part of 'home_focus_view.dart';

class HomeFocusAgenda extends StatelessWidget {
  final HomeOverview overview;
  final bool embedded;

  const HomeFocusAgenda({
    super.key,
    required this.overview,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final entries =
        overview.attentionItems
            .where((item) => item.occurredAt != null)
            .toList(growable: false)
          ..sort(
            (left, right) => left.occurredAt!.compareTo(right.occurredAt!),
          );
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        embedded ? 0 : 24,
        28,
        embedded ? 0 : 24,
        36,
      ),
      child: Column(
        key: const Key('home_focus_agenda'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FocusDateHeader(date: now),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            const _FocusAgendaEmpty()
          else
            _FocusTimeline(entries: entries.take(6).toList(growable: false)),
          const SizedBox(height: 16),
          _FocusAgendaFooter(overview: overview),
        ],
      ),
    );

    if (embedded) return content;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        key: const PageStorageKey('home-focus-agenda'),
        children: [content],
      ),
    );
  }
}

class _FocusDateHeader extends StatelessWidget {
  final DateTime date;

  const _FocusDateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            children: [
              Text(
                '${date.day}',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.6,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _focusWeekday(date.weekday),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.month} 月 · 今天',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusTimeline extends StatelessWidget {
  final List<HomeAttentionItem> entries;

  const _FocusTimeline({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned(
          left: 42,
          top: 4,
          bottom: 12,
          child: Container(width: 1, color: theme.colorScheme.outlineVariant),
        ),
        Column(
          children: [
            for (final entry in entries) _FocusTimelineRow(item: entry),
          ],
        ),
      ],
    );
  }
}

class _FocusTimelineRow extends StatelessWidget {
  final HomeAttentionItem item;

  const _FocusTimelineRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _focusLevelColor(item.level, theme.semanticColors);
    final local = item.occurredAt!.toLocal();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 31,
            child: Text(
              DateFormat('HH:mm').format(local),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: tone,
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.surface, width: 2),
              boxShadow: [BoxShadow(color: tone, spreadRadius: 1)],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _focusItemDetail(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusAgendaEmpty extends StatelessWidget {
  const _FocusAgendaEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 24,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '今天没有带时间的关注事项',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusAgendaFooter extends StatelessWidget {
  final HomeOverview overview;

  const _FocusAgendaFooter({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = overview.syncSummary;
    final hasError =
        sync.error?.trim().isNotEmpty == true || sync.failedAssetCount > 0;
    final title = hasError
        ? '同步需要检查'
        : sync.connected || sync.hasSynced == true
        ? '数据已同步'
        : '当前离线可用';
    final detail = hasError
        ? (sync.error?.trim().isNotEmpty == true
              ? sync.error!.trim()
              : '${sync.failedAssetCount} 个附件同步失败')
        : sync.lastSyncedAt != null
        ? '最近同步 ${DateFormat('MM/dd HH:mm').format(sync.lastSyncedAt!.toLocal())}'
        : overview.sourceMode == 'local'
        ? '首页来自本地计算，不依赖网络'
        : '云端读取失败时会自动回退本地';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _focusWeekday(int weekday) {
  const labels = ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  return labels[weekday.clamp(1, 7)];
}
