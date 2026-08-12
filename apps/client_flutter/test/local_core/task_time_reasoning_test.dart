import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/task/local_task_time_reasoning.dart';
import 'package:client_flutter/data/local_core/task/local_task_time_reasoning_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalTaskRecord task({DateTime? dueAt, String description = '提前到站并完成安检'}) {
    final createdAt = DateTime.utc(2026, 8, 10, 8);
    return LocalTaskRecord(
      id: 'task-time-reasoning',
      title: '赶高铁去外地开会',
      description: description,
      dueAt: dueAt,
      remindAt: null,
      priority: 'high',
      taskStatus: 'todo',
      completedAt: null,
      status: 'active',
      revision: 1,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  test('time facts do exact cross-day math before AI reasoning', () {
    final facts = LocalTaskTimeReasoning.inspect(
      task(dueAt: DateTime.parse('2026-08-12T08:30:00+08:00')),
      now: DateTime.parse('2026-08-11T23:09:00+08:00'),
    );

    expect(facts.hasDeadline, isTrue);
    expect(facts.remainingSeconds, 9 * 3600 + 21 * 60);
    expect(facts.isOverdue, isFalse);
    expect(facts.nowUtc.toIso8601String(), '2026-08-11T15:09:00.000Z');
    expect(facts.dueAtUtc?.toIso8601String(), '2026-08-12T00:30:00.000Z');
    expect(facts.toAiPayload()['remaining_seconds'], 33660);
  });

  test('AI timing validation derives thresholds and rejects bad windows', () {
    final facts = LocalTaskTimeReasoning.inspect(
      task(dueAt: DateTime.parse('2026-08-12T08:30:00+08:00')),
      now: DateTime.parse('2026-08-12T08:10:00+08:00'),
    );
    final valid = LocalTaskTimeReasoning.validate(
      facts,
      const LocalAiTaskTimingProposal(
        important: true,
        urgentLeadSeconds: 3600,
        superUrgentLeadSeconds: 1800,
      ),
    );

    expect(valid.valid, isTrue);
    expect(valid.stage, 'super_urgent');
    expect(
      valid.urgentStartAtUtc?.toIso8601String(),
      '2026-08-11T23:30:00.000Z',
    );
    expect(
      valid.superUrgentStartAtUtc?.toIso8601String(),
      '2026-08-12T00:00:00.000Z',
    );

    final invalid = LocalTaskTimeReasoning.validate(
      facts,
      const LocalAiTaskTimingProposal(
        important: true,
        urgentLeadSeconds: 1800,
        superUrgentLeadSeconds: 3600,
      ),
    );
    expect(invalid.valid, isFalse);
    expect(
      invalid.errors,
      contains('super_urgent_lead_seconds 必须小于等于 urgent_lead_seconds'),
    );

    expect(LocalTaskTimeReasoning.parseDurationSeconds('1d'), 86400);
    expect(LocalTaskTimeReasoning.parseDurationSeconds('3h'), 10800);
    expect(LocalTaskTimeReasoning.parseDurationSeconds('40分钟'), 2400);
    expect(LocalTaskTimeReasoning.parseDurationSeconds('1.5h'), 5400);
    expect(LocalTaskTimeReasoning.parseDurationSeconds('15秒'), 15);
    final exactMinimum = LocalTaskTimeReasoning.sumDurationSeconds([
      LocalTaskTimeReasoning.parseDurationSeconds('40m'),
      LocalTaskTimeReasoning.parseDurationSeconds('20m'),
    ]);
    final underestimated = LocalTaskTimeReasoning.validate(
      facts,
      const LocalAiTaskTimingProposal(
        important: true,
        urgentLeadSeconds: 1800,
        superUrgentLeadSeconds: 1200,
      ),
      minimumUrgentLeadSeconds: exactMinimum,
    );
    expect(exactMinimum, 3600);
    expect(underestimated.valid, isFalse);
    expect(
      underestimated.errors,
      contains('urgent_lead_seconds 小于精确时间约束 3600 秒'),
    );
  });

  test('time tool session forces exact duration checks before validation', () {
    final session = LocalTaskTimeToolSession.forTask(
      task(
        dueAt: DateTime.parse('2026-08-12T08:30:00+08:00'),
        description: '到车站路程约40分钟，至少提前20分钟进站。',
      ),
      now: DateTime.parse('2026-08-12T07:35:00+08:00'),
    );
    expect(session.isComplete, isFalse);
    expect(session.requiredToolName, liflyTimeInspectToolName);

    final beforeInspect = session.execute(liflyTimeValidateToolName, const {
      'important': true,
      'urgent_lead_seconds': 3600,
      'super_urgent_lead_seconds': 1200,
    });
    expect(beforeInspect, {
      'valid': false,
      'errors': ['必须先调用 lifly_time_inspect'],
    });

    final inspected = session.execute(liflyTimeInspectToolName, const {});
    expect(inspected['valid'], isTrue);
    expect(inspected['remaining_seconds'], 3300);
    expect(inspected['duration_candidates'], ['40分钟', '20分钟']);
    expect(session.requiredToolName, liflyTimeSumDurationsToolName);

    final premature = session.execute(liflyTimeValidateToolName, const {
      'important': true,
      'urgent_lead_seconds': 1800,
      'super_urgent_lead_seconds': 1200,
    });
    expect(premature, {
      'valid': false,
      'errors': ['检测到明确时长，必须先调用 lifly_time_sum_durations'],
    });

    final invented = session.execute(liflyTimeSumDurationsToolName, const {
      'durations': ['3小时'],
    });
    expect(invented, {
      'valid': false,
      'errors': ['3小时 不在任务的精确时长候选中'],
    });

    final summed = session.execute(liflyTimeSumDurationsToolName, const {
      'durations': ['40分钟', '20分钟'],
    });
    expect(summed['valid'], isTrue);
    expect(summed['parts_seconds'], [2400, 1200]);
    expect(summed['minimum_urgent_lead_seconds'], 3600);
    expect(summed['hard_start_missed'], isTrue);
    expect(session.requiredToolName, liflyTimeValidateToolName);

    final underestimated = session.execute(liflyTimeValidateToolName, const {
      'important': true,
      'urgent_lead_seconds': 1800,
      'super_urgent_lead_seconds': 1200,
    });
    expect(underestimated['valid'], isFalse);
    expect(underestimated['errors'], ['urgent_lead_seconds 小于精确时间约束 3600 秒']);
    expect(session.requiredToolName, liflyTimeValidateToolName);
    expect(session.continuationPrompt(), contains(liflyTimeValidateToolName));

    final repaired = session.execute(liflyTimeValidateToolName, const {
      'important': true,
      'urgent_lead_seconds': 3600,
      'super_urgent_lead_seconds': 1200,
    });
    expect(repaired['valid'], isTrue);
    expect(repaired['stage'], 'urgent');
    expect(repaired['minimum_urgent_lead_seconds'], 3600);
    expect(session.isComplete, isTrue);
    expect(session.requiredToolName, isNull);

    final definitions = localTaskTimeToolDefinitions();
    expect(
      definitions
          .map((item) {
            final function = item['function']! as Map<String, Object?>;
            return function['name'];
          })
          .toList(growable: false),
      [
        liflyTimeInspectToolName,
        liflyTimeSumDurationsToolName,
        liflyTimeValidateToolName,
      ],
    );
  });

  test('deadline-free tasks cannot receive invented timing windows', () {
    final facts = LocalTaskTimeReasoning.inspect(
      task(),
      now: DateTime.utc(2026, 8, 12, 1),
    );
    final validation = LocalTaskTimeReasoning.validate(
      facts,
      const LocalAiTaskTimingProposal(
        important: false,
        urgentLeadSeconds: 600,
        superUrgentLeadSeconds: 300,
      ),
    );

    expect(facts.remainingSeconds, isNull);
    expect(validation.valid, isFalse);
    expect(validation.errors, contains('无截止时间任务不得生成紧急时间窗口'));
    final contract = LocalTaskTimeReasoning.aiContract();
    expect(contract['validation_required'], isTrue);
    expect(contract['tool_flow'], [
      liflyTimeInspectToolName,
      liflyTimeSumDurationsToolName,
      liflyTimeValidateToolName,
    ]);
    expect(contract['system_prompt'], contains('不得自行进行日期、时区、时间差或单位换算'));
    expect(contract['system_prompt'], contains('有截止时间时两个 lead 都必须是正整数秒'));
    expect(
      contract['system_prompt'],
      contains('只有 is_overdue=true 才表示 DDL 已经过期'),
    );
    expect(contract['system_prompt'], contains('session 完成前禁止输出自然语言'));
    expect(
      contract['completion_gate'],
      '只有 time tool session 完成 valid=true 的 lifly_time_validate 后，才允许接受模型最终输出。',
    );
    expect(contract['host_policy'], contains('session.required_tool_name'));
  });
}
