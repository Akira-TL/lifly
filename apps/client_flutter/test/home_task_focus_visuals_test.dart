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

  test(
    'urgency progress is remaining time divided by the AI urgency window',
    () {
      expect(
        homeTaskUrgencyRatio(
          const Duration(hours: 36),
          const Duration(days: 3),
        ),
        0.5,
      );
      expect(
        homeTaskUrgencyRatio(
          const Duration(minutes: 5),
          const Duration(minutes: 5),
        ),
        1,
      );
      expect(
        homeTaskUrgencyRatio(
          const Duration(minutes: 2, seconds: 30),
          const Duration(minutes: 5),
        ),
        0.5,
      );
      expect(
        homeTaskUrgencyRatio(const Duration(days: 8), const Duration(days: 3)),
        1,
      );
      expect(homeTaskUrgencyRatio(Duration.zero, const Duration(hours: 1)), 0);
    },
  );

  test(
    'countdown selects seconds minutes hours and days from remaining time',
    () {
      expect(homeTaskCountdownLabel(const Duration(seconds: 45)), '45秒');
      expect(homeTaskCountdownLabel(const Duration(minutes: 15)), '15分钟');
      expect(homeTaskCountdownLabel(const Duration(hours: 5)), '5小时');
      expect(homeTaskCountdownLabel(const Duration(days: 3, hours: 2)), '3天');
      expect(homeTaskCountdownLabel(const Duration(seconds: -1)), '0秒');
    },
  );
}
