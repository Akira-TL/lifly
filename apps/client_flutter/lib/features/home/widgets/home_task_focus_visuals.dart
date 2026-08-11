import 'dart:async';

import 'package:client_flutter/app/theme/lifly_semantic_colors.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:flutter/material.dart';

enum HomeTaskUrgencyStage { notUrgent, urgent, superUrgent }

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

HomeTaskUrgencyStage homeTaskUrgencyStage(
  Duration remaining,
  Duration urgencyWindow,
  Duration superUrgencyWindow,
) {
  if (remaining <= superUrgencyWindow) {
    return HomeTaskUrgencyStage.superUrgent;
  }
  if (remaining <= urgencyWindow) return HomeTaskUrgencyStage.urgent;
  return HomeTaskUrgencyStage.notUrgent;
}

double homeTaskTimelineProgress({
  required DateTime now,
  required DateTime createdAt,
  required DateTime dueAt,
  required Duration urgencyWindow,
}) {
  if (urgencyWindow <= Duration.zero) return 1;
  final urgentStart = dueAt.subtract(urgencyWindow);
  if (now.isBefore(urgentStart)) {
    final totalCalm = urgentStart.difference(createdAt);
    if (totalCalm <= Duration.zero) return 0;
    final calmRemaining = urgentStart.difference(now);
    return (calmRemaining.inMilliseconds / totalCalm.inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }
  final urgentElapsed = now.difference(urgentStart);
  return (urgentElapsed.inMilliseconds / urgencyWindow.inMilliseconds)
      .clamp(0, 1)
      .toDouble();
}

Duration? homeNextUrgencyTransition(
  Iterable<HomeAttentionItem> items,
  DateTime now,
) {
  Duration? next;
  for (final item in items) {
    final dueAt = item.occurredAt;
    if (dueAt == null || item.urgencyWindowSeconds <= 0) continue;
    final thresholds = <DateTime>[
      dueAt.subtract(Duration(seconds: item.urgencyWindowSeconds)),
      if (item.superUrgencyWindowSeconds > 0)
        dueAt.subtract(Duration(seconds: item.superUrgencyWindowSeconds)),
    ];
    for (final threshold in thresholds) {
      final delay = threshold.difference(now);
      if (delay <= Duration.zero) continue;
      if (next == null || delay < next) next = delay;
    }
  }
  return next;
}

String homeTaskCountdownLabel(
  Duration remaining, {
  required HomeTaskUrgencyStage stage,
}) {
  if (remaining <= Duration.zero) return '00:00';
  final ticking =
      stage == HomeTaskUrgencyStage.superUrgent ||
      remaining <= const Duration(minutes: 30);
  if (ticking) {
    final seconds = remaining.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final restSeconds = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${restSeconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${restSeconds.toString().padLeft(2, '0')}';
  }
  if (remaining >= const Duration(days: 1)) return '${remaining.inDays}d';
  if (remaining >= const Duration(hours: 1)) return '${remaining.inHours}h';
  return '${remaining.inMinutes}m';
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
            widget.item.urgencyWindowSeconds ||
        oldWidget.item.superUrgencyWindowSeconds !=
            widget.item.superUrgencyWindowSeconds ||
        oldWidget.item.progressStartedAt != widget.item.progressStartedAt) {
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
    final urgencyWindow = Duration(seconds: widget.item.urgencyWindowSeconds);
    final superWindow = Duration(
      seconds: widget.item.superUrgencyWindowSeconds,
    );
    final stage = homeTaskUrgencyStage(remaining, urgencyWindow, superWindow);
    var delay = switch (stage) {
      HomeTaskUrgencyStage.superUrgent => const Duration(seconds: 1),
      HomeTaskUrgencyStage.urgent =>
        remaining <= const Duration(minutes: 30)
            ? const Duration(seconds: 1)
            : const Duration(minutes: 1),
      HomeTaskUrgencyStage.notUrgent => const Duration(minutes: 5),
    };
    final untilUrgent = remaining - urgencyWindow;
    if (untilUrgent > Duration.zero && untilUrgent < delay) delay = untilUrgent;
    final untilSuper = remaining - superWindow;
    if (untilSuper > Duration.zero && untilSuper < delay) delay = untilSuper;
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
    final superWindow = Duration(seconds: item.superUrgencyWindowSeconds);
    final stage = homeTaskUrgencyStage(remaining, urgencyWindow, superWindow);
    final currentQuadrant = homeTaskCurrentQuadrant(
      item.quadrant,
      remaining,
      urgencyWindow,
    );
    final tone = homeTaskQuadrantColor(currentQuadrant, theme.semanticColors);
    final urgentStart = dueAt?.subtract(urgencyWindow);
    final fallbackStart = urgentStart?.subtract(urgencyWindow);
    final progressStart = item.progressStartedAt?.toLocal() ?? fallbackStart;
    final ratio = dueAt == null || progressStart == null
        ? 1.0
        : homeTaskTimelineProgress(
            now: _now,
            createdAt: progressStart,
            dueAt: dueAt,
            urgencyWindow: urgencyWindow,
          );
    final stageLabel = switch (stage) {
      HomeTaskUrgencyStage.notUrgent => '未进入紧急阶段',
      HomeTaskUrgencyStage.urgent => '紧急',
      HomeTaskUrgencyStage.superUrgent => '超级紧急',
    };

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${homeTaskQuadrantLabel(currentQuadrant)}，$stageLabel',
      child: SizedBox(
        height: 60,
        child: DecoratedBox(
          key: Key('${widget.keyPrefix}_item_${item.entityId}'),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(
              color: stage == HomeTaskUrgencyStage.superUrgent
                  ? tone.withValues(alpha: 0.52)
                  : theme.colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(7),
            boxShadow: stage == HomeTaskUrgencyStage.superUrgent
                ? [
                    BoxShadow(
                      color: tone.withValues(alpha: 0.12),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Column(
              children: [
                Container(
                  key: Key('${widget.keyPrefix}_urgency_bar_${item.entityId}'),
                  height: stage == HomeTaskUrgencyStage.superUrgent ? 5 : 4,
                  color: tone.withValues(
                    alpha: stage == HomeTaskUrgencyStage.notUrgent
                        ? 0.10
                        : 0.16,
                  ),
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    widthFactor: ratio,
                    heightFactor: 1,
                    alignment: Alignment.centerLeft,
                    child: ColoredBox(
                      color: stage == HomeTaskUrgencyStage.urgent
                          ? tone.withValues(alpha: 0.82)
                          : tone,
                    ),
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
                        dueAt == null
                            ? '—'
                            : homeTaskCountdownLabel(remaining, stage: stage),
                        key: Key(
                          '${widget.keyPrefix}_countdown_${item.entityId}',
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tone,
                          fontWeight: stage == HomeTaskUrgencyStage.superUrgent
                              ? FontWeight.w900
                              : FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          letterSpacing:
                              stage == HomeTaskUrgencyStage.superUrgent
                              ? 0.35
                              : null,
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
