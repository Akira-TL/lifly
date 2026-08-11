import 'dart:async';

import 'package:client_flutter/app/theme/lifly_semantic_colors.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:flutter/material.dart';

Color homeTaskQuadrantColor(String quadrant, LiflySemanticColors colors) {
  return switch (quadrant) {
    'urgent_important' || 'important_urgent' => colors.critical,
    'urgent_not_important' || 'not_important_urgent' => colors.warning,
    'not_urgent_important' || 'important_not_urgent' => colors.info,
    'not_urgent_not_important' || 'not_important_not_urgent' => colors.success,
    _ => colors.neutral,
  };
}

String homeTaskQuadrantLabel(String quadrant) {
  return switch (quadrant) {
    'urgent_important' || 'important_urgent' => '紧急重要',
    'urgent_not_important' || 'not_important_urgent' => '紧急不重要',
    'not_urgent_important' || 'important_not_urgent' => '不紧急重要',
    'not_urgent_not_important' || 'not_important_not_urgent' => '不紧急不重要',
    _ => '待判断',
  };
}

String homeTaskCurrentQuadrant(
  String storedQuadrant,
  Duration remaining,
  Duration urgencyWindow,
) {
  final important = switch (storedQuadrant) {
    'urgent_important' ||
    'important_urgent' ||
    'not_urgent_important' ||
    'important_not_urgent' => true,
    _ => false,
  };
  final urgent = remaining <= urgencyWindow;
  if (urgent && important) return 'urgent_important';
  if (urgent) return 'urgent_not_important';
  if (important) return 'not_urgent_important';
  return 'not_urgent_not_important';
}

double homeTaskUrgencyRatio(Duration remaining, Duration urgencyWindow) {
  if (remaining <= Duration.zero) return 0;
  if (urgencyWindow <= Duration.zero) return 1;
  final ratio = remaining.inMilliseconds / urgencyWindow.inMilliseconds;
  return ratio.clamp(0, 1).toDouble();
}

Duration? homeNextUrgencyTransition(
  Iterable<HomeAttentionItem> items,
  DateTime now,
) {
  Duration? next;
  for (final item in items) {
    final dueAt = item.occurredAt;
    if (dueAt == null || item.urgencyWindowSeconds <= 0) continue;
    final transitionAt = dueAt.subtract(
      Duration(seconds: item.urgencyWindowSeconds),
    );
    final delay = transitionAt.difference(now);
    if (delay <= Duration.zero) continue;
    if (next == null || delay < next) next = delay;
  }
  return next;
}

String homeTaskCountdownLabel(Duration remaining) {
  if (remaining <= Duration.zero) return '0秒';
  if (remaining < const Duration(minutes: 1)) {
    return '${remaining.inSeconds}秒';
  }
  if (remaining < const Duration(hours: 1)) {
    return '${remaining.inMinutes}分钟';
  }
  if (remaining < const Duration(days: 1)) {
    return '${remaining.inHours}小时';
  }
  return '${remaining.inDays}天';
}

class HomeTaskFocusTile extends StatefulWidget {
  final HomeAttentionItem item;
  final Future<void> Function(HomeAttentionItem item) onCompleteTask;
  final String keyPrefix;

  const HomeTaskFocusTile({
    super.key,
    required this.item,
    required this.onCompleteTask,
    required this.keyPrefix,
  });

  @override
  State<HomeTaskFocusTile> createState() => _HomeTaskFocusTileState();
}

class _HomeTaskFocusTileState extends State<HomeTaskFocusTile> {
  Timer? _timer;
  bool _completing = false;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
  }

  @override
  void didUpdateWidget(covariant HomeTaskFocusTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.occurredAt != widget.item.occurredAt ||
        oldWidget.item.urgencyWindowSeconds !=
            widget.item.urgencyWindowSeconds) {
      _timer?.cancel();
      _now = DateTime.now();
      _scheduleNextTick();
    }
  }

  void _scheduleNextTick() {
    final dueAt = widget.item.occurredAt?.toLocal();
    if (dueAt == null) return;
    final remaining = dueAt.difference(_now);
    if (remaining <= Duration.zero) return;
    final displayDelay = remaining < const Duration(minutes: 1)
        ? const Duration(seconds: 1)
        : remaining < const Duration(hours: 1)
        ? const Duration(minutes: 1)
        : remaining < const Duration(days: 1)
        ? const Duration(hours: 1)
        : const Duration(days: 1);
    final urgencyWindow = Duration(seconds: widget.item.urgencyWindowSeconds);
    final untilUrgent = remaining - urgencyWindow;
    final delay = untilUrgent > Duration.zero && untilUrgent < displayDelay
        ? untilUrgent
        : displayDelay;
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleNextTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_completing || widget.item.entityType != 'task') return;
    setState(() => _completing = true);
    try {
      await widget.onCompleteTask(widget.item);
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final dueAt = item.occurredAt?.toLocal();
    final remaining = dueAt?.difference(_now) ?? Duration.zero;
    final urgencyWindow = Duration(seconds: item.urgencyWindowSeconds);
    final currentQuadrant = homeTaskCurrentQuadrant(
      item.quadrant,
      remaining,
      urgencyWindow,
    );
    final tone = homeTaskQuadrantColor(currentQuadrant, theme.semanticColors);
    final ratio = dueAt == null
        ? 1.0
        : homeTaskUrgencyRatio(remaining, urgencyWindow);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: homeTaskQuadrantLabel(currentQuadrant),
      child: SizedBox(
        height: 60,
        child: DecoratedBox(
          key: Key('${widget.keyPrefix}_item_${item.entityId}'),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(7),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Column(
              children: [
                Container(
                  key: Key('${widget.keyPrefix}_urgency_bar_${item.entityId}'),
                  height: 4,
                  color: tone.withValues(alpha: 0.16),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: ratio,
                    child: ColoredBox(color: tone),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (item.entityType == 'task')
                        IconButton(
                          key: Key(
                            '${widget.keyPrefix}_complete_${item.entityId}',
                          ),
                          tooltip: '完成任务',
                          onPressed: _completing ? null : _complete,
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          padding: EdgeInsets.zero,
                          icon: _completing
                              ? const SizedBox.square(
                                  dimension: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.radio_button_unchecked,
                                  size: 20,
                                ),
                        )
                      else
                        const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        dueAt == null ? '—' : homeTaskCountdownLabel(remaining),
                        key: Key(
                          '${widget.keyPrefix}_countdown_${item.entityId}',
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
