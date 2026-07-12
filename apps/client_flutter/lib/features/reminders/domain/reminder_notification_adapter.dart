class ReminderNotificationRequest {
  final String reminderId;
  final String idempotencyKey;
  final String title;
  final String body;
  final DateTime remindAt;
  final String channel;
  final Map<String, Object?> payload;

  const ReminderNotificationRequest({
    required this.reminderId,
    required this.idempotencyKey,
    required this.title,
    required this.body,
    required this.remindAt,
    required this.channel,
    required this.payload,
  });
}

class ReminderNotificationResult {
  final bool delivered;
  final String? externalId;
  final String? error;
  final int? retryAfterSeconds;

  const ReminderNotificationResult._({
    required this.delivered,
    required this.externalId,
    required this.error,
    required this.retryAfterSeconds,
  });

  const ReminderNotificationResult.delivered({String? externalId})
      : this._(
          delivered: true,
          externalId: externalId,
          error: null,
          retryAfterSeconds: null,
        );

  const ReminderNotificationResult.failed({
    required String error,
    int? retryAfterSeconds,
  }) : this._(
          delivered: false,
          externalId: null,
          error: error,
          retryAfterSeconds: retryAfterSeconds,
        );
}

abstract class ReminderNotificationAdapter {
  String get platform;

  /// Implementations must treat [ReminderNotificationRequest.idempotencyKey]
  /// as stable across retries and avoid duplicate user-visible notifications.
  Future<ReminderNotificationResult> deliver(
    ReminderNotificationRequest request,
  );

  Future<void> cancel({
    required String idempotencyKey,
    String? externalId,
  });
}
