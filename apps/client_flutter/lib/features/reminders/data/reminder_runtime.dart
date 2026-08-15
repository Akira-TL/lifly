import 'dart:async';

import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/features/reminders/data/reminder_dispatcher.dart';

typedef ReminderTimerFactory =
    Timer Function(Duration delay, void Function() callback);

class ReminderRuntime {
  final ReminderDispatcher dispatcher;
  final ReminderTimerFactory timerFactory;
  final Duration rescanInterval;
  final void Function(Object error, StackTrace stackTrace)? onError;

  Timer? _timer;
  bool _disposed = false;

  ReminderRuntime({
    required this.dispatcher,
    ReminderTimerFactory? timerFactory,
    this.rescanInterval = const Duration(minutes: 1),
    this.onError,
  }) : timerFactory = timerFactory ?? Timer.new {
    if (rescanInterval <= Duration.zero) {
      throw ArgumentError.value(
        rescanInterval,
        'rescanInterval',
        'must be greater than zero',
      );
    }
  }

  Future<ReminderDispatchBatchResult> start() => _dispatchAndSchedule();

  Future<ReminderDispatchBatchResult> onResumed() => _dispatchAndSchedule();

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<ReminderDispatchBatchResult> _dispatchAndSchedule() async {
    if (_disposed) {
      throw StateError('ReminderRuntime has been disposed');
    }
    _timer?.cancel();
    _timer = null;
    final result = await dispatcher.dispatchDue();
    await _scheduleNextWake();
    return result;
  }

  Future<void> _scheduleNextWake() async {
    final current = dispatcher.now().toUtc();
    final context = LocalCoreContext.flutterUser(
      userId: dispatcher.userId,
      now: current,
    );
    final reminderGroups = await Future.wait([
      dispatcher.localCore.listTaskReminders({
        'status': 'pending',
        'limit': 100,
      }, context),
      dispatcher.localCore.listTaskReminders({
        'status': 'failed',
        'limit': 100,
      }, context),
    ]);
    final reminders = reminderGroups
        .expand((items) => items)
        .where((item) => item.attemptCount < item.maxAttempts);
    DateTime? nextWakeAt;
    for (final reminder in reminders) {
      final candidate = _effectiveWakeAt(reminder);
      if (nextWakeAt == null || candidate.isBefore(nextWakeAt)) {
        nextWakeAt = candidate;
      }
    }

    final untilNext = nextWakeAt?.difference(current);
    final delay = untilNext == null
        ? rescanInterval
        : _boundedWakeDelay(untilNext, rescanInterval);
    if (_disposed) return;
    _timer?.cancel();
    _timer = timerFactory(delay, _onTimer);
  }

  DateTime _effectiveWakeAt(LocalReminderRecord reminder) {
    var wakeAt = reminder.remindAt.toUtc();
    final nextAttemptAt = reminder.nextAttemptAt?.toUtc();
    if (nextAttemptAt != null && nextAttemptAt.isAfter(wakeAt)) {
      wakeAt = nextAttemptAt;
    }
    final leaseUntil = reminder.leaseUntil?.toUtc();
    if (leaseUntil != null && leaseUntil.isAfter(wakeAt)) {
      wakeAt = leaseUntil;
    }
    return wakeAt;
  }

  Duration _boundedWakeDelay(Duration untilNext, Duration safetyRescan) {
    if (untilNext <= Duration.zero) {
      const retryFloor = Duration(seconds: 5);
      return safetyRescan < retryFloor ? safetyRescan : retryFloor;
    }
    return untilNext < safetyRescan ? untilNext : safetyRescan;
  }

  void _onTimer() {
    if (_disposed) return;
    _timer = null;
    unawaited(_runTimerCycle());
  }

  Future<void> _runTimerCycle() async {
    try {
      await _dispatchAndSchedule();
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      if (!_disposed && _timer == null) {
        _timer = timerFactory(rescanInterval, _onTimer);
      }
    }
  }
}
