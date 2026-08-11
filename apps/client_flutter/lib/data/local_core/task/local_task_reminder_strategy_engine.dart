import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/task/local_task_time_reasoning.dart';

class LocalTaskReminderSuggestion {
  final String warningLevel;
  final String warningReason;
  final int? preparationWindowDays;
  final DateTime? aiSuggestedRemindAt;

  const LocalTaskReminderSuggestion({
    required this.warningLevel,
    required this.warningReason,
    required this.preparationWindowDays,
    required this.aiSuggestedRemindAt,
  });
}

class LocalTaskReminderStrategyEngine {
  const LocalTaskReminderStrategyEngine();

  LocalTaskReminderSuggestion? suggest(
    LocalTaskRecord task, {
    required DateTime now,
  }) {
    final facts = LocalTaskTimeReasoning.inspect(task, now: now);
    final baseline = facts.nowUtc;
    final dueAt = facts.dueAtUtc;
    final window = _preparationWindow(
      '${task.title}\n${task.description ?? ''}',
    );
    if (dueAt == null && window == null) return null;

    if (dueAt == null) {
      return LocalTaskReminderSuggestion(
        warningLevel: 'normal',
        warningReason: window?.reason ?? '任务需要进一步确认提醒时间。',
        preparationWindowDays: window?.days,
        aiSuggestedRemindAt: null,
      );
    }

    if (facts.isOverdue) {
      return LocalTaskReminderSuggestion(
        warningLevel: 'critical',
        warningReason: '任务已过截止时间，需要立即处理。',
        preparationWindowDays: 0,
        aiSuggestedRemindAt: baseline,
      );
    }

    final remaining = Duration(seconds: facts.remainingSeconds ?? 0);
    if (task.priority == 'urgent' || remaining <= const Duration(hours: 6)) {
      return LocalTaskReminderSuggestion(
        warningLevel: 'critical',
        warningReason: '任务距离截止时间很近，需要立即关注。',
        preparationWindowDays: 0,
        aiSuggestedRemindAt: _maxDate(
          baseline,
          dueAt.subtract(const Duration(hours: 2)),
        ),
      );
    }

    final resolvedWindow = window ?? _defaultWindow(remaining, task.priority);
    final remindAt = _suggestedRemindAt(dueAt, baseline, resolvedWindow.days);
    return LocalTaskReminderSuggestion(
      warningLevel: _warningLevel(
        dueAt: dueAt,
        now: baseline,
        days: resolvedWindow.days,
        priority: task.priority,
      ),
      warningReason: resolvedWindow.reason,
      preparationWindowDays: resolvedWindow.days,
      aiSuggestedRemindAt: remindAt,
    );
  }

  _PreparationWindow? _preparationWindow(String text) {
    const rules = <_PreparationWindowRule>[
      _PreparationWindowRule('考试', 7, '考试类任务通常需要提前一周准备。'),
      _PreparationWindowRule('签证', 7, '签证/证件类事项周期较长，建议提前准备。'),
      _PreparationWindowRule('旅行', 3, '出行类任务需要提前整理行程和物品。'),
      _PreparationWindowRule('露营', 3, '露营需要提前检查装备和采购。'),
      _PreparationWindowRule('出行', 3, '出行类任务需要提前准备。'),
      _PreparationWindowRule('项目', 2, '项目类任务通常需要提前拆解和推进。'),
      _PreparationWindowRule('周报', 1, '报告类任务建议提前一天整理材料。'),
      _PreparationWindowRule('报告', 1, '报告类任务建议提前一天整理材料。'),
      _PreparationWindowRule('提交', 1, '提交类任务建议提前一天检查。'),
      _PreparationWindowRule('房租', 0, '支付类任务临近截止时需要明确提醒。'),
    ];
    for (final rule in rules) {
      if (text.contains(rule.keyword)) {
        return _PreparationWindow(rule.days, rule.reason);
      }
    }
    return null;
  }

  _PreparationWindow _defaultWindow(Duration remaining, String priority) {
    if (priority == 'high') {
      return const _PreparationWindow(1, '高优先级任务建议至少提前一天提醒。');
    }
    if (remaining >= const Duration(days: 7)) {
      return const _PreparationWindow(3, '截止时间较远，建议提前三天开始准备。');
    }
    if (remaining >= const Duration(days: 2)) {
      return const _PreparationWindow(1, '未来几天截止，建议提前一天提醒。');
    }
    return const _PreparationWindow(0, '任务即将截止，建议当天提醒。');
  }

  DateTime _suggestedRemindAt(DateTime dueAt, DateTime now, int? days) {
    final candidate = days == null
        ? dueAt
        : days <= 0
        ? dueAt.subtract(const Duration(hours: 2))
        : dueAt.subtract(Duration(days: days));
    return _maxDate(now, candidate);
  }

  String _warningLevel({
    required DateTime dueAt,
    required DateTime now,
    required int? days,
    required String priority,
  }) {
    if (priority == 'urgent') return 'critical';
    if (dueAt.isBefore(now.add(const Duration(hours: 12)))) return 'critical';
    if (priority == 'high') return 'warning';
    if (days != null && days > 0) return 'warning';
    if (dueAt.isBefore(now.add(const Duration(days: 1)))) return 'warning';
    return 'normal';
  }

  DateTime _maxDate(DateTime a, DateTime b) {
    return a.isAfter(b) ? a : b;
  }
}

class _PreparationWindowRule {
  final String keyword;
  final int days;
  final String reason;

  const _PreparationWindowRule(this.keyword, this.days, this.reason);
}

class _PreparationWindow {
  final int days;
  final String reason;

  const _PreparationWindow(this.days, this.reason);
}
