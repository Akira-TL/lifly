import 'package:client_flutter/data/local_core/local_core_models.dart';

const int _maxAiLeadSeconds = 365 * 24 * 60 * 60;
const Map<String, int> _durationUnitSeconds = {
  'd': 86400,
  'day': 86400,
  'days': 86400,
  '天': 86400,
  'h': 3600,
  'hr': 3600,
  'hour': 3600,
  'hours': 3600,
  '小时': 3600,
  'm': 60,
  'min': 60,
  'minute': 60,
  'minutes': 60,
  '分钟': 60,
  '分': 60,
  's': 1,
  'sec': 1,
  'second': 1,
  'seconds': 1,
  '秒': 1,
};

class LocalTaskTimeFacts {
  final DateTime nowUtc;
  final DateTime? dueAtUtc;
  final int? remainingSeconds;
  final bool isOverdue;

  const LocalTaskTimeFacts({
    required this.nowUtc,
    required this.dueAtUtc,
    required this.remainingSeconds,
    required this.isOverdue,
  });

  bool get hasDeadline => dueAtUtc != null;

  Map<String, Object?> toAiPayload() {
    return {
      'tool_version': 'lifly.task_time_reasoning.v1',
      'has_deadline': hasDeadline,
      'now_utc': nowUtc.toIso8601String(),
      'due_at_utc': dueAtUtc?.toIso8601String(),
      'remaining_seconds': remainingSeconds,
      'is_overdue': isOverdue,
    };
  }
}

class LocalAiTaskTimingProposal {
  final bool important;
  final int? urgentLeadSeconds;
  final int? superUrgentLeadSeconds;

  const LocalAiTaskTimingProposal({
    required this.important,
    required this.urgentLeadSeconds,
    required this.superUrgentLeadSeconds,
  });
}

class LocalAiTaskTimingValidation {
  final bool valid;
  final List<String> errors;
  final String? stage;
  final DateTime? urgentStartAtUtc;
  final DateTime? superUrgentStartAtUtc;

  const LocalAiTaskTimingValidation({
    required this.valid,
    required this.errors,
    required this.stage,
    required this.urgentStartAtUtc,
    required this.superUrgentStartAtUtc,
  });
}

class LocalTaskTimeReasoning {
  const LocalTaskTimeReasoning._();

  static LocalTaskTimeFacts inspect(
    LocalTaskRecord task, {
    required DateTime now,
  }) {
    final nowUtc = now.toUtc();
    final dueAtUtc = task.dueAt?.toUtc();
    final remainingSeconds = dueAtUtc?.difference(nowUtc).inSeconds;
    return LocalTaskTimeFacts(
      nowUtc: nowUtc,
      dueAtUtc: dueAtUtc,
      remainingSeconds: remainingSeconds,
      isOverdue: remainingSeconds != null && remainingSeconds < 0,
    );
  }

  static int parseDurationSeconds(String token) {
    final match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*(d|day|days|天|h|hr|hour|hours|小时|m|min|minute|minutes|分钟|分|s|sec|second|seconds|秒)\s*$',
      caseSensitive: false,
    ).firstMatch(token);
    if (match == null) {
      throw ArgumentError.value(token, 'token', '精确时长格式无效，应类似 40m、2小时、1.5h');
    }
    final rawAmount = match.group(1)!;
    if (rawAmount.startsWith('-')) {
      throw ArgumentError.value(token, 'token', '精确时长必须是非负整数秒');
    }
    final amountParts = rawAmount.split('.');
    final fractionDigits = amountParts.length == 2 ? amountParts[1].length : 0;
    final scale = _pow10(fractionDigits);
    final scaledAmount = int.parse(amountParts.join());
    final unit = match.group(2)!.toLowerCase();
    final scaledSeconds = scaledAmount * _durationUnitSeconds[unit]!;
    if (scaledSeconds % scale != 0) {
      throw ArgumentError.value(token, 'token', '精确时长换算后必须是完整秒');
    }
    final seconds = scaledSeconds ~/ scale;
    if (seconds > _maxAiLeadSeconds) {
      throw ArgumentError.value(token, 'token', '单个精确时长超过 31536000 秒');
    }
    return seconds;
  }

  static int sumDurationSeconds(Iterable<int> partsSeconds) {
    var total = 0;
    for (final value in partsSeconds) {
      if (value < 0) {
        throw ArgumentError.value(value, 'partsSeconds', '精确时长必须是非负整数秒');
      }
      total += value;
    }
    if (total > _maxAiLeadSeconds) {
      throw ArgumentError.value(total, 'partsSeconds', '精确时长总和超过 31536000 秒');
    }
    return total;
  }

  static LocalAiTaskTimingValidation validate(
    LocalTaskTimeFacts facts,
    LocalAiTaskTimingProposal proposal, {
    int? minimumUrgentLeadSeconds,
  }) {
    final errors = <String>[];
    final urgent = proposal.urgentLeadSeconds;
    final superUrgent = proposal.superUrgentLeadSeconds;

    if (!facts.hasDeadline) {
      if (urgent != null || superUrgent != null) {
        errors.add('无截止时间任务不得生成紧急时间窗口');
      }
      return LocalAiTaskTimingValidation(
        valid: errors.isEmpty,
        errors: List.unmodifiable(errors),
        stage: errors.isEmpty ? 'no_deadline' : null,
        urgentStartAtUtc: null,
        superUrgentStartAtUtc: null,
      );
    }

    if (!_isValidLead(urgent)) {
      errors.add('urgent_lead_seconds 必须是 1 到 31536000 的整数秒');
    }
    if (!_isValidLead(superUrgent)) {
      errors.add('super_urgent_lead_seconds 必须是 1 到 31536000 的整数秒');
    }
    if (_isValidLead(urgent) &&
        _isValidLead(superUrgent) &&
        superUrgent! > urgent!) {
      errors.add('super_urgent_lead_seconds 必须小于等于 urgent_lead_seconds');
    }
    if (minimumUrgentLeadSeconds != null) {
      if (!_isValidLead(minimumUrgentLeadSeconds)) {
        errors.add('minimum_urgent_lead_seconds 必须是 1 到 31536000 的整数秒');
      } else if (_isValidLead(urgent) && urgent! < minimumUrgentLeadSeconds) {
        errors.add('urgent_lead_seconds 小于精确时间约束 $minimumUrgentLeadSeconds 秒');
      }
    }

    if (errors.isNotEmpty) {
      return LocalAiTaskTimingValidation(
        valid: false,
        errors: List.unmodifiable(errors),
        stage: null,
        urgentStartAtUtc: null,
        superUrgentStartAtUtc: null,
      );
    }

    final dueAtUtc = facts.dueAtUtc!;
    final remainingSeconds = facts.remainingSeconds!;
    final urgentSeconds = urgent!;
    final superUrgentSeconds = superUrgent!;
    final urgentStartAtUtc = dueAtUtc.subtract(
      Duration(seconds: urgentSeconds),
    );
    final superUrgentStartAtUtc = dueAtUtc.subtract(
      Duration(seconds: superUrgentSeconds),
    );
    final stage = remainingSeconds < 0
        ? 'overdue'
        : remainingSeconds <= superUrgentSeconds
        ? 'super_urgent'
        : remainingSeconds <= urgentSeconds
        ? 'urgent'
        : 'not_urgent';

    return LocalAiTaskTimingValidation(
      valid: true,
      errors: const [],
      stage: stage,
      urgentStartAtUtc: urgentStartAtUtc,
      superUrgentStartAtUtc: superUrgentStartAtUtc,
    );
  }

  static Map<String, Object> aiContract() {
    return {
      'version': 'lifly.task_time_reasoning.v1',
      'rules': const [
        '精确时间计算必须使用 time_facts，不得由模型自行做日期或时区算术。',
        '模型只估计重要性以及两个提前量，提前量统一使用整数秒。',
        '任务文本包含明确时长时，必须先用 sum_durations 做精确加总，并把结果作为最小紧急提前量交给 validate。',
        '模型输出后必须调用 validate；校验失败时修正输出，禁止绕过校验。',
        '无截止时间任务的两个提前量必须为 null。',
      ],
      'proposal_fields': const [
        'important',
        'urgent_lead_seconds',
        'super_urgent_lead_seconds',
      ],
      'tools': const {
        'inspect': '计算 now / DDL / remaining_seconds / overdue，禁止模型自行做日期算术。',
        'sum_durations': '对任务文本中明确给出的多个耗时做精确整数秒加总。',
        'validate': '校验 AI 提前量与精确最小时长，并计算 urgent_start / super_start / 当前阶段。',
      },
      'tool_flow': const [
        'inspect',
        'sum_exact_durations_when_present',
        'semantic_proposal',
        'validate',
        'retry_on_validation_error',
      ],
      'validation_required': true,
    };
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var index = 0; index < exponent; index += 1) {
      result *= 10;
    }
    return result;
  }

  static bool _isValidLead(int? value) {
    return value != null && value > 0 && value <= _maxAiLeadSeconds;
  }
}
