import 'package:client_flutter/features/reminders/data/android_reminder_notification_adapter.dart';
import 'package:client_flutter/features/reminders/domain/reminder_notification_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _ShownNotification {
  final int id;
  final String title;
  final String body;
  final String payload;

  const _ShownNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });
}

class _FakeAndroidNotificationGateway
    implements AndroidReminderNotificationGateway {
  bool permissionGranted = true;
  int initializeCalls = 0;
  int permissionCalls = 0;
  final List<_ShownNotification> shown = [];
  final List<int> cancelled = [];

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<bool> ensurePermission() async {
    permissionCalls += 1;
    return permissionGranted;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    shown.add(
      _ShownNotification(id: id, title: title, body: body, payload: payload),
    );
  }

  @override
  Future<void> cancel({required int id}) async {
    cancelled.add(id);
  }
}

void main() {
  test(
    'android adapter delivers with stable notification id and payload',
    () async {
      final gateway = _FakeAndroidNotificationGateway();
      final adapter = AndroidReminderNotificationAdapter(gateway: gateway);
      final request = ReminderNotificationRequest(
        reminderId: 'reminder-42',
        idempotencyKey: 'reminder-42',
        title: '提交周报',
        body: '整理本周工作并提交',
        remindAt: DateTime.utc(2026, 8, 15, 12),
        channel: 'system',
        payload: const {'target_type': 'task', 'target_id': 'task-7'},
      );

      final first = await adapter.deliver(request);
      final second = await adapter.deliver(request);

      expect(first.delivered, isTrue);
      expect(second.delivered, isTrue);
      expect(first.externalId, second.externalId);
      expect(gateway.shown, hasLength(2));
      expect(gateway.shown.first.id, gateway.shown.last.id);
      expect(gateway.shown.first.title, '提交周报');
      expect(gateway.shown.first.body, '整理本周工作并提交');
      expect(
        gateway.shown.first.payload,
        contains('"reminder_id":"reminder-42"'),
      );
      expect(gateway.shown.first.payload, contains('"target_id":"task-7"'));
    },
  );

  test(
    'android adapter keeps reminder identity authoritative in payload',
    () async {
      final gateway = _FakeAndroidNotificationGateway();
      final adapter = AndroidReminderNotificationAdapter(gateway: gateway);
      final request = ReminderNotificationRequest(
        reminderId: 'reminder-real',
        idempotencyKey: 'reminder-real',
        title: '提醒',
        body: '处理任务',
        remindAt: DateTime.utc(2026, 8, 15, 12),
        channel: 'system',
        payload: const {'reminder_id': 'spoofed', 'idempotency_key': 'spoofed'},
      );

      await adapter.deliver(request);

      expect(
        gateway.shown.single.payload,
        contains('"reminder_id":"reminder-real"'),
      );
      expect(
        gateway.shown.single.payload,
        contains('"idempotency_key":"reminder-real"'),
      );
      expect(gateway.shown.single.payload, isNot(contains('spoofed')));
    },
  );

  test('android adapter reports denied permission without showing', () async {
    final gateway = _FakeAndroidNotificationGateway()
      ..permissionGranted = false;
    final adapter = AndroidReminderNotificationAdapter(gateway: gateway);

    final result = await adapter.deliver(
      ReminderNotificationRequest(
        reminderId: 'reminder-denied',
        idempotencyKey: 'reminder-denied',
        title: '提醒',
        body: '处理任务',
        remindAt: DateTime.utc(2026, 8, 15, 12),
        channel: 'system',
        payload: const {},
      ),
    );

    expect(result.delivered, isFalse);
    expect(result.error, 'notification permission denied');
    expect(gateway.shown, isEmpty);
  });

  test(
    'android adapter cancellation reuses external or deterministic id',
    () async {
      final gateway = _FakeAndroidNotificationGateway();
      final adapter = AndroidReminderNotificationAdapter(gateway: gateway);

      await adapter.cancel(
        idempotencyKey: 'reminder-external',
        externalId: 'android:91',
      );
      await adapter.cancel(idempotencyKey: 'reminder-derived');

      expect(gateway.cancelled.first, 91);
      expect(
        gateway.cancelled.last,
        AndroidReminderNotificationAdapter.notificationIdFor(
          'reminder-derived',
        ),
      );
    },
  );
}
