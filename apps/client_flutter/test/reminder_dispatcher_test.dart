import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/features/reminders/data/reminder_dispatcher.dart';
import 'package:client_flutter/features/reminders/domain/reminder_notification_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _QueueReminderAdapter implements ReminderNotificationAdapter {
  final List<ReminderNotificationResult> results;
  final List<ReminderNotificationRequest> requests = [];
  final List<String> cancelledKeys = [];

  _QueueReminderAdapter(this.results);

  @override
  String get platform => 'test';

  @override
  Future<ReminderNotificationResult> deliver(
    ReminderNotificationRequest request,
  ) async {
    requests.add(request);
    if (results.isEmpty) {
      throw StateError('No queued reminder result');
    }
    return results.removeAt(0);
  }

  @override
  Future<void> cancel({
    required String idempotencyKey,
    String? externalId,
  }) async {
    cancelledKeys.add(idempotencyKey);
  }
}

void main() {
  final now = DateTime.utc(2026, 7, 11, 10);

  Future<String> createDueReminder(FakeLocalCoreBridge core) async {
    final context = LocalCoreContext.flutterUser(now: now);
    final task = await core.createTask({
      'title': '提交周报',
      'description': '整理本周工作并提交',
      'due_at': now.add(const Duration(hours: 2)).toIso8601String(),
    }, context);
    await core.confirmTaskReminderStrategy({
      'task_id': task.id,
      'warning_level': 'warning',
      'warning_reason': '需要提前整理材料',
      'ai_suggested_remind_at': now.toIso8601String(),
      'source': 'user',
    }, context);
    final reminders = await core.listTaskReminders({
      'status': 'pending',
    }, context);
    return reminders.single.id;
  }

  test('dispatcher delivers due reminder with stable idempotency key', () async {
    final core = FakeLocalCoreBridge();
    final reminderId = await createDueReminder(core);
    final adapter = _QueueReminderAdapter([
      const ReminderNotificationResult.delivered(
        externalId: 'test-notification-1',
      ),
    ]);
    final dispatcher = ReminderDispatcher(
      localCore: core,
      adapter: adapter,
      now: () => now,
    );

    final result = await dispatcher.dispatchDue();
    final delivered = await core.listTaskReminders({
      'status': 'delivered',
    }, LocalCoreContext.flutterUser(now: now));

    expect(result.claimed, 1);
    expect(result.delivered, 1);
    expect(result.failed, 0);
    expect(adapter.requests.single.reminderId, reminderId);
    expect(adapter.requests.single.idempotencyKey, reminderId);
    expect(adapter.requests.single.title, '提交周报');
    expect(delivered.single.externalId, 'test-notification-1');
    expect(delivered.single.attemptCount, 1);
  });

  test('dispatcher records failure then succeeds after manual retry', () async {
    final core = FakeLocalCoreBridge();
    final reminderId = await createDueReminder(core);
    final adapter = _QueueReminderAdapter([
      const ReminderNotificationResult.failed(
        error: 'notification permission denied',
        retryAfterSeconds: 0,
      ),
      const ReminderNotificationResult.delivered(
        externalId: 'test-notification-2',
      ),
    ]);
    final dispatcher = ReminderDispatcher(
      localCore: core,
      adapter: adapter,
      now: () => now,
    );

    final failedBatch = await dispatcher.dispatchDue();
    final failed = await core.listTaskReminders({
      'status': 'failed',
    }, LocalCoreContext.flutterUser(now: now));

    expect(failedBatch.failed, 1);
    expect(failed.single.id, reminderId);
    expect(failed.single.lastError, 'notification permission denied');

    await core.retryTaskReminder({
      'reminder_id': reminderId,
      'reset_attempts': true,
    }, LocalCoreContext.flutterUser(now: now));
    final deliveredBatch = await dispatcher.dispatchDue();
    final delivered = await core.listTaskReminders({
      'status': 'delivered',
    }, LocalCoreContext.flutterUser(now: now));

    expect(deliveredBatch.delivered, 1);
    expect(delivered.single.id, reminderId);
    expect(delivered.single.externalId, 'test-notification-2');
    expect(adapter.requests.map((item) => item.idempotencyKey), [
      reminderId,
      reminderId,
    ]);
  });
}
