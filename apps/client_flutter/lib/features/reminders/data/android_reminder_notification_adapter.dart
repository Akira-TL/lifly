import 'dart:convert';

import 'package:client_flutter/features/reminders/domain/reminder_notification_adapter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract interface class AndroidReminderNotificationGateway {
  Future<void> initialize();

  Future<bool> ensurePermission();

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  Future<void> cancel({required int id});
}

class FlutterLocalNotificationsAndroidGateway
    implements AndroidReminderNotificationGateway {
  static const _channelId = 'lifly_reminders';
  static const _channelName = 'Lifly 提醒';
  static const _channelDescription = '任务提醒与待办通知';

  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;

  FlutterLocalNotificationsAndroidGateway({
    FlutterLocalNotificationsPlugin? plugin,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    final initialized = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
      ),
    );
    if (initialized == false) {
      throw StateError('flutter_local_notifications initialization failed');
    }
    _initialized = true;
  }

  @override
  Future<bool> ensurePermission() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    if (await android.areNotificationsEnabled() == true) return true;
    return await android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) {
    return plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  @override
  Future<void> cancel({required int id}) {
    return plugin.cancel(id: id);
  }
}

class AndroidReminderNotificationAdapter
    implements ReminderNotificationAdapter {
  final AndroidReminderNotificationGateway gateway;

  AndroidReminderNotificationAdapter({
    AndroidReminderNotificationGateway? gateway,
  }) : gateway = gateway ?? FlutterLocalNotificationsAndroidGateway();

  @override
  String get platform => 'android';

  @override
  Future<ReminderNotificationResult> deliver(
    ReminderNotificationRequest request,
  ) async {
    try {
      await gateway.initialize();
      if (!await gateway.ensurePermission()) {
        return const ReminderNotificationResult.failed(
          error: 'notification permission denied',
        );
      }
      final notificationId = notificationIdFor(request.idempotencyKey);
      await gateway.show(
        id: notificationId,
        title: request.title,
        body: request.body,
        payload: jsonEncode({
          ...request.payload,
          'reminder_id': request.reminderId,
          'idempotency_key': request.idempotencyKey,
          'remind_at': request.remindAt.toUtc().toIso8601String(),
          'channel': request.channel,
        }),
      );
      return ReminderNotificationResult.delivered(
        externalId: 'android:$notificationId',
      );
    } catch (error) {
      return ReminderNotificationResult.failed(
        error: 'android notification delivery failed: $error',
      );
    }
  }

  @override
  Future<void> cancel({
    required String idempotencyKey,
    String? externalId,
  }) async {
    await gateway.initialize();
    await gateway.cancel(
      id:
          _notificationIdFromExternalId(externalId) ??
          notificationIdFor(idempotencyKey),
    );
  }

  static int notificationIdFor(String idempotencyKey) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(idempotencyKey)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static int? _notificationIdFromExternalId(String? externalId) {
    if (externalId == null || !externalId.startsWith('android:')) return null;
    return int.tryParse(externalId.substring('android:'.length));
  }
}
