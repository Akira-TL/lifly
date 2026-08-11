import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/task/local_task_time_reasoning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalTaskRecord task({DateTime? dueAt}) {
    final createdAt = DateTime.utc(2026, 8, 10, 8);
    return LocalTaskRecord(
      id: 'task-time-reasoning',
      title: '赶高铁去外地开会',
      description: '提前到站并完成安检',
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

    final exactMinimum = LocalTaskTimeReasoning.sumDurationSeconds([
      40 * 60,
      20 * 60,
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
      'inspect',
      'sum_exact_durations_when_present',
      'semantic_proposal',
      'validate',
      'retry_on_validation_error',
    ]);
  });
}
