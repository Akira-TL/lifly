import 'package:client_flutter/data/local_core/local_core_models.dart';

const int _maxAiLeadSeconds = 365 * 24 * 60 * 60;
const String _durationUnitPattern =
    r'd|day|days|天|h|hr|hour|hours|小时|m|min|minute|minutes|分钟|分|s|sec|second|seconds|秒';
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

  static List<String> extractDurationTokens(String text) {
    return _durationPattern(anchored: false)
        .allMatches(text)
        .map((match) => match.group(0)!.trim())
        .toList(growable: false);
  }

  static int parseDurationSeconds(String token) {
    final match = _durationPattern(anchored: true).firstMatch(token);
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
        'lifly_time_inspect':
            '读取绑定任务的精确 now / DDL / remaining / overdue 与原始时长候选。',
        'lifly_time_sum_durations': '选择硬性前置耗时候选，由工具完成单位换算和求和。',
        'lifly_time_validate': '用绑定的精确时间事实与硬性耗时校验 AI 建议并计算最终阶段。',
      },
      'tool_flow': const [
        'lifly_time_inspect',
        'lifly_time_sum_durations',
        'lifly_time_validate',
      ],
      'system_prompt':
          '你是 Lifly 任务语义判断器。涉及精确时间时，不得自行进行日期、时区、时间差或单位换算。'
          '第一步必须调用 lifly_time_inspect。若 duration_candidates 非空，必须调用 '
          'lifly_time_sum_durations，并且 durations 只能从候选中选择真正影响最晚开始行动的硬性前置耗时；'
          '如果候选都不属于硬性耗时则传空数组。你只负责判断 important、urgent_lead_seconds 和 '
          'super_urgent_lead_seconds；有截止时间时两个 lead 都必须是正整数秒且 super 不得大于 urgent，'
          '无截止时间时两个 lead 必须为 null。只有 is_overdue=true 才表示 DDL 已经过期；'
          'hard_start_missed=true 只表示最安全开始时间已经错过。session 完成前禁止输出自然语言或复述工具结果，'
          '只能继续发出必需的 tool call。最后必须调用 lifly_time_validate。若返回 valid=false，读取 errors '
          '修正语义建议后再次调用 lifly_time_validate，禁止绕过校验或修改工具返回的精确事实。',
      'completion_gate':
          '只有 time tool session 完成 valid=true 的 lifly_time_validate 后，才允许接受模型最终输出。',
      'host_policy':
          '每一轮只向模型暴露 session.required_tool_name 对应的一个 tool schema；'
          'session 未完成时忽略自然语言最终输出，并用 continuation_prompt 要求继续工具调用。',
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

RegExp _durationPattern({required bool anchored}) {
  final core = r'(-?\d+(?:\.\d+)?)\s*(' + _durationUnitPattern + ')';
  return RegExp(
    anchored ? r'^\s*' + core + r'\s*$' : core,
    caseSensitive: false,
  );
}
