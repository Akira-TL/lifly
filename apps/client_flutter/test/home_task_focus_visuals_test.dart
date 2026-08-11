import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:client_flutter/features/home/widgets/home_task_focus_visuals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quadrant urgency flips when remaining time enters the task window', () {
    expect(
      homeTaskCurrentQuadrant(
        'not_urgent_important',
        const Duration(hours: 2),
        const Duration(hours: 1),
      ),
      'not_urgent_important',
    );
    expect(
      homeTaskCurrentQuadrant(
        'not_urgent_important',
        const Duration(minutes: 45),
        const Duration(hours: 1),
      ),
      'urgent_important',
    );
    expect(
      homeTaskCurrentQuadrant(
        'not_urgent_not_important',
        const Duration(minutes: 4),
        const Duration(minutes: 5),
      ),
      'urgent_not_important',
    );
  });

  test('next urgency transition picks the nearest future task threshold', () {
    final now = DateTime.utc(2026, 8, 11, 10);
    final items = [
      HomeAttentionItem(
        id: 'task-1',
        type: 'task_focus',
        level: 'info',
        quadrant: 'not_urgent_important',
        urgencyWindowSeconds: const Duration(hours: 3).inSeconds,
        title: 'long task',
        description: null,
        entityType: 'task',
        entityId: 'task-1',
        occurredAt: now.add(const Duration(hours: 6)),
      ),
      HomeAttentionItem(
        id: 'task-2',
        type: 'task_focus',
        level: 'normal',
        quadrant: 'not_urgent_not_important',
        urgencyWindowSeconds: const Duration(minutes: 15).inSeconds,
        title: 'short task',
        description: null,
        entityType: 'task',
        entityId: 'task-2',
        occurredAt: now.add(const Duration(hours: 1)),
      ),
    ];

    expect(homeNextUrgencyTransition(items, now), const Duration(minutes: 45));
  });

  test('urgency stage distinguishes calm urgent and super urgent', () {
    expect(
      homeTaskUrgencyStage(
        const Duration(hours: 5),
        const Duration(hours: 4),
        const Duration(hours: 1),
      ),
      HomeTaskUrgencyStage.notUrgent,
    );
    expect(
      homeTaskUrgencyStage(
        const Duration(hours: 2),
        const Duration(hours: 4),
        const Duration(hours: 1),
      ),
      HomeTaskUrgencyStage.urgent,
    );
    expect(
      homeTaskUrgencyStage(
        const Duration(minutes: 30),
        const Duration(hours: 4),
        const Duration(hours: 1),
      ),
      HomeTaskUrgencyStage.superUrgent,
    );
  });

  test(
    'top progress shrinks before urgency then grows after urgency starts',
    () {
      final createdAt = DateTime.utc(2026, 8, 11, 10);
      final dueAt = DateTime.utc(2026, 8, 11, 20);
      const urgencyWindow = Duration(hours: 4);

      expect(
        homeTaskTimelineProgress(
          now: createdAt,
          createdAt: createdAt,
          dueAt: dueAt,
          urgencyWindow: urgencyWindow,
        ),
        1,
      );
      expect(
        homeTaskTimelineProgress(
          now: DateTime.utc(2026, 8, 11, 13),
          createdAt: createdAt,
          dueAt: dueAt,
          urgencyWindow: urgencyWindow,
        ),
        0.5,
      );
      expect(
        homeTaskTimelineProgress(
          now: DateTime.utc(2026, 8, 11, 16),
          createdAt: createdAt,
          dueAt: dueAt,
          urgencyWindow: urgencyWindow,
        ),
        0,
      );
      expect(
        homeTaskTimelineProgress(
          now: DateTime.utc(2026, 8, 11, 18),
          createdAt: createdAt,
          dueAt: dueAt,
          urgencyWindow: urgencyWindow,
        ),
        0.5,
      );
      expect(
        homeTaskTimelineProgress(
          now: dueAt,
          createdAt: createdAt,
          dueAt: dueAt,
          urgencyWindow: urgencyWindow,
        ),
        1,
      );
    },
  );

  test('countdown uses compact units and ticking clocks for critical time', () {
    expect(
      homeTaskCountdownLabel(
        const Duration(days: 3, hours: 2),
        stage: HomeTaskUrgencyStage.notUrgent,
      ),
      '3d',
    );
    expect(
      homeTaskCountdownLabel(
        const Duration(hours: 5),
        stage: HomeTaskUrgencyStage.urgent,
      ),
      '5h',
    );
    expect(
      homeTaskCountdownLabel(
        const Duration(minutes: 45),
        stage: HomeTaskUrgencyStage.urgent,
      ),
      '45m',
    );
    expect(
      homeTaskCountdownLabel(
        const Duration(hours: 5, minutes: 4, seconds: 3),
        stage: HomeTaskUrgencyStage.superUrgent,
      ),
      '05:04:03',
    );
    expect(
      homeTaskCountdownLabel(
        const Duration(minutes: 18, seconds: 42),
        stage: HomeTaskUrgencyStage.superUrgent,
      ),
      '18:42',
    );
    expect(
      homeTaskCountdownLabel(
        const Duration(minutes: 29, seconds: 4),
        stage: HomeTaskUrgencyStage.urgent,
      ),
      '29:04',
    );
  });
}
