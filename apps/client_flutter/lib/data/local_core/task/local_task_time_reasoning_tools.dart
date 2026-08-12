import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/task/local_task_time_reasoning.dart';

const String liflyTimeInspectToolName = 'lifly_time_inspect';
const String liflyTimeSumDurationsToolName = 'lifly_time_sum_durations';
const String liflyTimeValidateToolName = 'lifly_time_validate';

class LocalTaskTimeToolSession {
  final LocalTaskTimeFacts facts;
  final List<String> durationCandidates;
  bool _inspected = false;
  bool _durationCheckCompleted;
  int? _minimumUrgentLeadSeconds;
  bool _validationComplete = false;

  LocalTaskTimeToolSession._({
    required this.facts,
    required this.durationCandidates,
    required bool durationCheckCompleted,
  }) : _durationCheckCompleted = durationCheckCompleted;

  factory LocalTaskTimeToolSession.forTask(
    LocalTaskRecord task, {
    required DateTime now,
  }) {
    final text = '${task.title}\n${task.description ?? ''}';
    final candidates = LocalTaskTimeReasoning.extractDurationTokens(text);
    return LocalTaskTimeToolSession._(
      facts: LocalTaskTimeReasoning.inspect(task, now: now),
      durationCandidates: List.unmodifiable(candidates),
      durationCheckCompleted: candidates.isEmpty,
    );
  }

  bool get isComplete => _validationComplete;

  String? get requiredToolName {
    if (_validationComplete) return null;
    if (!_inspected) return liflyTimeInspectToolName;
    if (durationCandidates.isNotEmpty && !_durationCheckCompleted) {
      return liflyTimeSumDurationsToolName;
    }
    return liflyTimeValidateToolName;
  }

  String continuationPrompt() {
    final required = requiredToolName;
    if (required == null) return '';
    return '时间推理流程尚未完成。现在必须调用 $required，不要输出最终解释；'
        '若工具返回 valid=false，按 errors 修正后继续调用必需工具。';
  }

  Map<String, Object?> execute(String name, Map<String, Object?> arguments) {
    try {
      return switch (name) {
        liflyTimeInspectToolName => _inspect(),
        liflyTimeSumDurationsToolName => _sumDurations(arguments),
        liflyTimeValidateToolName => _validate(arguments),
        _ => throw ArgumentError('未知时间工具：$name'),
      };
    } on ArgumentError catch (error) {
      return {
        'valid': false,
        'errors': [_argumentErrorMessage(error)],
      };
    }
  }

  Map<String, Object?> _inspect() {
    _inspected = true;
    return {
      'valid': true,
      ...facts.toAiPayload(),
      'duration_candidates': durationCandidates,
      'duration_check_required': durationCandidates.isNotEmpty,
    };
  }

  Map<String, Object?> _sumDurations(Map<String, Object?> arguments) {
    if (!_inspected) throw ArgumentError('必须先调用 lifly_time_inspect');
    final durations = _requireStringList(arguments, 'durations');
    _ensureSelectedCandidates(durations, durationCandidates);
    final partsSeconds = durations
        .map(LocalTaskTimeReasoning.parseDurationSeconds)
        .toList(growable: false);
    final total = LocalTaskTimeReasoning.sumDurationSeconds(partsSeconds);
    _durationCheckCompleted = true;
    _minimumUrgentLeadSeconds = total > 0 ? total : null;
    _validationComplete = false;
    final hardStartMissed =
        facts.remainingSeconds != null && total > facts.remainingSeconds!;
    return {
      'valid': true,
      'durations': durations,
      'parts_seconds': partsSeconds,
      'minimum_urgent_lead_seconds': total,
      'hard_start_missed': hardStartMissed,
    };
  }

  Map<String, Object?> _validate(Map<String, Object?> arguments) {
    if (!_inspected) {
      return const {
        'valid': false,
        'errors': ['必须先调用 lifly_time_inspect'],
      };
    }
    if (durationCandidates.isNotEmpty && !_durationCheckCompleted) {
      return const {
        'valid': false,
        'errors': ['检测到明确时长，必须先调用 lifly_time_sum_durations'],
      };
    }
    final validation = LocalTaskTimeReasoning.validate(
      facts,
      LocalAiTaskTimingProposal(
        important: _requireBool(arguments, 'important'),
        urgentLeadSeconds: _optionalInt(arguments, 'urgent_lead_seconds'),
        superUrgentLeadSeconds: _optionalInt(
          arguments,
          'super_urgent_lead_seconds',
        ),
      ),
      minimumUrgentLeadSeconds: _minimumUrgentLeadSeconds,
    );
    _validationComplete = validation.valid;
    return {
      'valid': validation.valid,
      'errors': validation.errors,
      'stage': validation.stage,
      'minimum_urgent_lead_seconds': _minimumUrgentLeadSeconds ?? 0,
      'urgent_start_at_utc': validation.urgentStartAtUtc?.toIso8601String(),
      'super_urgent_start_at_utc': validation.superUrgentStartAtUtc
          ?.toIso8601String(),
    };
  }
}

List<Map<String, Object?>> localTaskTimeToolDefinitions() {
  const nullableInteger = {
    'anyOf': [
      {'type': 'integer', 'minimum': 1, 'maximum': 31536000},
      {'type': 'null'},
    ],
  };
  return [
    {
      'type': 'function',
      'function': {
        'name': liflyTimeInspectToolName,
        'description': '读取当前任务的精确时间事实。涉及日期、时区、剩余时间时必须先调用。',
        'parameters': {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': liflyTimeSumDurationsToolName,
        'description':
            '从 inspect 给出的 duration_candidates 中选择属于硬性前置耗时的项，由工具完成单位换算和求和。候选存在时必须调用，即使选择为空数组。',
        'parameters': {
          'type': 'object',
          'properties': {
            'durations': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['durations'],
          'additionalProperties': false,
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': liflyTimeValidateToolName,
        'description':
            '提交 AI 的重要性与紧急提前量建议；工具用绑定的精确时间事实和硬性耗时约束校验并计算最终阶段。校验失败必须修正后再次调用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'important': {'type': 'boolean'},
            'urgent_lead_seconds': nullableInteger,
            'super_urgent_lead_seconds': nullableInteger,
          },
          'required': [
            'important',
            'urgent_lead_seconds',
            'super_urgent_lead_seconds',
          ],
          'additionalProperties': false,
        },
      },
    },
  ];
}

void _ensureSelectedCandidates(List<String> selected, List<String> candidates) {
  final available = <String, int>{};
  for (final token in candidates) {
    available[token] = (available[token] ?? 0) + 1;
  }
  final used = <String, int>{};
  for (final token in selected) {
    used[token] = (used[token] ?? 0) + 1;
    if (used[token]! > (available[token] ?? 0)) {
      throw ArgumentError('$token 不在任务的精确时长候选中');
    }
  }
}

List<String> _requireStringList(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw ArgumentError('$key 必须是字符串数组');
  }
  return value.cast<String>().toList(growable: false);
}

bool _requireBool(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! bool) throw ArgumentError('$key 必须是布尔值');
  return value;
}

int? _optionalInt(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value == null) return null;
  if (value is! int) throw ArgumentError('$key 必须是整数或 null');
  return value;
}

String _argumentErrorMessage(ArgumentError error) {
  final message = error.message;
  return message == null ? error.toString() : '$message';
}
