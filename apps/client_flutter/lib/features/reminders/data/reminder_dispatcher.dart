import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/features/reminders/domain/reminder_notification_adapter.dart';

class ReminderDispatchBatchResult {
  final int claimed;
  final int delivered;
  final int failed;
  final List<String> errors;

  const ReminderDispatchBatchResult({
    required this.claimed,
    required this.delivered,
    required this.failed,
    required this.errors,
  });
}

class ReminderDispatcher {
  final LocalCoreBridge localCore;
  final ReminderNotificationAdapter adapter;
  final String userId;
  final DateTime Function() now;

  ReminderDispatcher({
    required this.localCore,
    required this.adapter,
    this.userId = 'local-dev',
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<ReminderDispatchBatchResult> dispatchDue({
    int limit = 20,
    int leaseSeconds = 120,
  }) async {
    final dispatchAt = now().toUtc();
    final context = LocalCoreContext.flutterUser(
      userId: userId,
      now: dispatchAt,
    );
    final claims = await localCore.claimDueTaskReminders({
      'limit': limit,
      'lease_seconds': leaseSeconds,
      'now': dispatchAt.toIso8601String(),
    }, context);

    var delivered = 0;
    var failed = 0;
    final errors = <String>[];
    for (final reminder in claims) {
      final dispatchToken = reminder.dispatchToken;
      if (dispatchToken == null || dispatchToken.isEmpty) {
        failed += 1;
        errors.add('Reminder ${reminder.id} was claimed without a dispatch token');
        continue;
      }
      try {
        final result = await adapter.deliver(
          _requestFor(reminder),
        );
        if (result.delivered) {
          await localCore.markTaskReminderDelivered({
            'reminder_id': reminder.id,
            'dispatch_token': dispatchToken,
            'external_id': result.externalId,
          }, context);
          delivered += 1;
        } else {
          final error = result.error ?? 'Unknown notification delivery failure';
          await localCore.markTaskReminderFailed({
            'reminder_id': reminder.id,
            'dispatch_token': dispatchToken,
            'error': error,
            'retry_after_seconds': result.retryAfterSeconds,
          }, context);
          failed += 1;
          errors.add('${reminder.id}: $error');
        }
      } catch (error) {
        try {
          await localCore.markTaskReminderFailed({
            'reminder_id': reminder.id,
            'dispatch_token': dispatchToken,
            'error': error.toString(),
          }, context);
        } catch (stateError) {
          errors.add('${reminder.id}: delivery=$error; state=$stateError');
          failed += 1;
          continue;
        }
        failed += 1;
        errors.add('${reminder.id}: $error');
      }
    }

    return ReminderDispatchBatchResult(
      claimed: claims.length,
      delivered: delivered,
      failed: failed,
      errors: List.unmodifiable(errors),
    );
  }

  ReminderNotificationRequest _requestFor(LocalReminderRecord reminder) {
    return ReminderNotificationRequest(
      reminderId: reminder.id,
      idempotencyKey: reminder.id,
      title: reminder.title?.trim().isNotEmpty == true
          ? reminder.title!.trim()
          : 'Lifly 提醒',
      body: reminder.body?.trim().isNotEmpty == true
          ? reminder.body!.trim()
          : '你有一项待处理任务',
      remindAt: reminder.remindAt,
      channel: reminder.channel,
      payload: {
        'target_type': reminder.targetType,
        'target_id': reminder.targetId,
        'platform': adapter.platform,
        'attempt_count': reminder.attemptCount,
      },
    );
  }
}
