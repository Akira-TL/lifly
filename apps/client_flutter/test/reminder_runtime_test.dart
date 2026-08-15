import 'dart:async';

import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/features/reminders/data/reminder_dispatcher.dart';
import 'package:client_flutter/features/reminders/data/reminder_runtime.dart';
import 'package:client_flutter/features/reminders/domain/reminder_notification_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeliveredReminderAdapter implements ReminderNotificationAdapter {
  final List<ReminderNotificationRequest> requests = [];

  @override
  String get platform => 'test';

  @override
  Future<ReminderNotificationResult> deliver(
    ReminderNotificationRequest request,
  ) async {
    requests.add(request);
    return ReminderNotificationResult.delivered(
      externalId: 'test:${request.reminderId}',
    );
  }

  @override
  Future<void> cancel({
    required String idempotencyKey,
    String? externalId,
  }) async {}
}

class _FakeTimer implements Timer {
  final void Function() callback;
  bool _active = true;

  _FakeTimer(this.callback);

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }
}

class _TimerCall {
  final Duration delay;
  final _FakeTimer timer;

  const _TimerCall(this.delay, this.timer);
}

class _FakeTimerFactory {
  final List<_TimerCall> calls = [];

  Timer create(Duration delay, void Function() callback) {
    final timer = _FakeTimer(callback);
    calls.add(_TimerCall(delay, timer));
    return timer;
  }
}

void main() {
  test('runtime recovers overdue reminder immediately on app start', () async {
    final now = DateTime.utc(2026, 8, 15, 10);
    final core = FakeLocalCoreBridge();
    final context = LocalCoreContext.flutterUser(now: now);
    final task = await core.createTask({
      'title': '路演提醒',
      'description': '检查 Android 真机通知',
      'due_at': now.add(const Duration(hours: 1)).toIso8601String(),
    }, context);
    await core.confirmTaskReminderStrategy({
      'task_id': task.id,
      'warning_level': 'warning',
      'warning_reason': '路演前检查',
      'ai_suggested_remind_at': now
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
      'source': 'user',
    }, context);
    final adapter = _DeliveredReminderAdapter();
    final timers = _FakeTimerFactory();
    final runtime = ReminderRuntime(
      dispatcher: ReminderDispatcher(
        localCore: core,
        adapter: adapter,
        now: () => now,
      ),
      timerFactory: timers.create,
      rescanInterval: const Duration(minutes: 1),
    );

    final result = await runtime.start();
    final delivered = await core.listTaskReminders({
      'status': 'delivered',
    }, context);

    expect(result.delivered, 1);
    expect(adapter.requests, hasLength(1));
    expect(delivered, hasLength(1));
    expect(timers.calls.single.delay, const Duration(minutes: 1));

    runtime.dispose();
  });

  test('runtime wakes at the next reminder before the safety rescan', () async {
    final now = DateTime.utc(2026, 8, 15, 10);
    final core = FakeLocalCoreBridge();
    final context = LocalCoreContext.flutterUser(now: now);
    final task = await core.createTask({
      'title': '五分钟后提醒',
      'due_at': now.add(const Duration(hours: 1)).toIso8601String(),
    }, context);
    await core.confirmTaskReminderStrategy({
      'task_id': task.id,
      'warning_level': 'warning',
      'warning_reason': '短时提醒',
      'ai_suggested_remind_at': now
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'source': 'user',
    }, context);
    final timers = _FakeTimerFactory();
    final runtime = ReminderRuntime(
      dispatcher: ReminderDispatcher(
        localCore: core,
        adapter: _DeliveredReminderAdapter(),
        now: () => now,
      ),
      timerFactory: timers.create,
      rescanInterval: const Duration(minutes: 30),
    );

    final result = await runtime.start();

    expect(result.claimed, 0);
    expect(timers.calls.single.delay, const Duration(minutes: 5));

    runtime.dispose();
  });

  test('runtime waits for an active lease then recovers on resume', () async {
    var current = DateTime.utc(2026, 8, 15, 10);
    final core = FakeLocalCoreBridge();
    final context = LocalCoreContext.flutterUser(now: current);
    final task = await core.createTask({
      'title': '崩溃恢复提醒',
      'due_at': current.add(const Duration(hours: 1)).toIso8601String(),
    }, context);
    await core.confirmTaskReminderStrategy({
      'task_id': task.id,
      'warning_level': 'warning',
      'warning_reason': '模拟进程在派发后崩溃',
      'ai_suggested_remind_at': current
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
      'source': 'user',
    }, context);
    final firstClaim = await core.claimDueTaskReminders({
      'now': current.toIso8601String(),
      'lease_seconds': 120,
    }, context);
    expect(firstClaim, hasLength(1));

    final adapter = _DeliveredReminderAdapter();
    final timers = _FakeTimerFactory();
    final runtime = ReminderRuntime(
      dispatcher: ReminderDispatcher(
        localCore: core,
        adapter: adapter,
        now: () => current,
      ),
      timerFactory: timers.create,
      rescanInterval: const Duration(minutes: 30),
    );

    final beforeLeaseExpiry = await runtime.start();

    expect(beforeLeaseExpiry.claimed, 0);
    expect(adapter.requests, isEmpty);
    expect(timers.calls.single.delay, const Duration(minutes: 2));

    current = current.add(const Duration(minutes: 2, seconds: 1));
    final recovered = await runtime.onResumed();

    expect(recovered.delivered, 1);
    expect(adapter.requests, hasLength(1));
    expect(timers.calls.first.timer.isActive, isFalse);

    runtime.dispose();
  });
}
