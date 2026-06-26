import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../database/database.dart';
import '../providers/settings_provider.dart';
import '../main.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  void Function(String title, String body, String type, String? itemId)? onNotificationSent;

  /// 检查是否允许发送通知（Android 13+ 需要运行时权限）
  Future<bool> _canPostNotifications() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      return status.isGranted;
    }
    return true;
  }

  /// 检查是否可以 schedule exact alarm（Android 12+ 需要 SCHEDULE_EXACT_ALARM）
  Future<bool> _canScheduleExactAlarms() async {
    if (Platform.isAndroid) {
      final status = await Permission.scheduleExactAlarm.status;
      return status.isGranted;
    }
    return true;
  }

  /// 打开系统设置页让用户开启“闹钟与提醒”权限
  Future<void> openExactAlarmSettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        data: 'package:com.nestback.shouna',
      );
      await intent.launch();
    } catch (e) {
      print('[NotificationService] Failed to open alarm settings: $e');
    }
  }

  Future<void> init() async {
    if (_initialized) return;

    try {
      tz.initializeTimeZones();
      print('[NotificationService] Timezone data initialized');

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
      );

      final result = await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _handleNotificationTap,
      );

      print('[NotificationService] Notification service initialized: $result');
      _initialized = true;
    } catch (e) {
      print('[NotificationService] Failed to initialize: $e');
    }
  }

  void _handleNotificationTap(NotificationResponse response) async {
    print('[NotificationService] Notification tapped');
    navigatorKey.currentState?.pushNamed('/notifications');
  }

  Future<void> scheduleExpireNotification(
    int notificationId,
    String itemName,
    DateTime notificationTime,
    String body,
  ) async {
    try {
      if (!_initialized) {
        print('[NotificationService] Not initialized, calling init...');
        await init();
      }

      if (!_initialized) {
        print('[NotificationService] Still not initialized');
        return;
      }

      final localNow = DateTime.now();
      final timezoneOffset = localNow.timeZoneOffset.inHours;
      
      print('[NotificationService] Local time: $localNow');
      print('[NotificationService] Timezone offset: UTC+$timezoneOffset');
      print('[NotificationService] Target local time: $notificationTime');

      final scheduledUtcTime = notificationTime.toUtc();

      final scheduledTime = tz.TZDateTime.from(scheduledUtcTime, tz.UTC);
      final now = tz.TZDateTime.now(tz.UTC);
      
      print('[NotificationService] Scheduling notification:');
      print('[NotificationService]   ID: $notificationId');
      print('[NotificationService]   Item: $itemName');
      print('[NotificationService]   Body: $body');
      print('[NotificationService]   Scheduled (UTC): $scheduledTime');
      print('[NotificationService]   Now (UTC): $now');
      print('[NotificationService]   Diff: ${scheduledTime.difference(now).inSeconds}s');

      if (scheduledTime.isBefore(now)) {
        print('[NotificationService] Time is in the past, skipping');
        return;
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'expire_reminder_channel',
        '过期提醒',
        channelDescription: '物品过期提醒通知',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/launcher_icon',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
        ongoing: false,
        autoCancel: true,
        category: AndroidNotificationCategory.reminder,
      );

      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidDetails);

      // Android 12+ 精确闹钟需要 SCHEDULE_EXACT_ALARM 权限；
      // 无权限时使用 inexact 模式降级，避免 SecurityException 导致闪退。
      final canScheduleExact = await _canScheduleExactAlarms();
      final scheduleMode = canScheduleExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      print('[NotificationService] Using schedule mode: $scheduleMode');

      await _notificationsPlugin.zonedSchedule(
        notificationId,
        itemName,
        body,
        scheduledTime,
        notificationDetails,
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('[NotificationService] Notification scheduled successfully');
    } catch (e, stackTrace) {
      print('[NotificationService] Failed to schedule: $e');
      print('[NotificationService] Stack trace: $stackTrace');
    }
  }

  Future<void> showNotification(int notificationId, String title, String body) async {
    try {
      if (!_initialized) {
        print('[NotificationService] Not initialized, calling init...');
        await init();
      }

      if (!_initialized) {
        print('[NotificationService] Still not initialized');
        return;
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'expire_reminder_channel',
        '过期提醒',
        channelDescription: '物品过期提醒通知',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/launcher_icon',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
        ongoing: false,
        autoCancel: true,
        category: AndroidNotificationCategory.reminder,
      );

      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidDetails);

      // Android 13+ 发送通知前检查权限，未授权时静默跳过避免异常
      if (!await _canPostNotifications()) {
        print('[NotificationService] Notification permission not granted, skipping show');
        return;
      }

      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        notificationDetails,
      );

      onNotificationSent?.call(title, body, 'expire', null);

      print('[NotificationService] Notification shown: $title');
    } catch (e, stackTrace) {
      print('[NotificationService] Failed to show: $e');
      print('[NotificationService] Stack trace: $stackTrace');
    }
  }

  Future<void> testNotification() async {
    print('[NotificationService] Testing immediate notification...');
    await showNotification(9999, '测试通知', '这是一条即时测试通知');
  }

  Future<void> testScheduledNotification() async {
    print('[NotificationService] Testing scheduled notification in 10 seconds...');
    final scheduledTime = DateTime.now().add(const Duration(seconds: 10));
    await scheduleExpireNotification(8888, '测试定时通知', scheduledTime, '10秒后触发');
  }

  Future<void> cancelNotification(int notificationId) async {
    try {
      await _notificationsPlugin.cancel(notificationId);
      print('[NotificationService] Canceled notification: $notificationId');
    } catch (e) {
      print('[NotificationService] Failed to cancel: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      print('[NotificationService] Canceled all notifications');
    } catch (e) {
      print('[NotificationService] Failed to cancel all: $e');
    }
  }

  Future<int?> _getItemExpireReminderOffset(AppDatabase db, String itemId) async {
    final attrs = await (db.select(db.attributes)
          ..where((t) => t.name.equals('过期提醒')))
        .get();
    if (attrs.isEmpty) return null;

    final itemAttrs = await (db.select(db.itemAttributes)
          ..where((t) => t.itemId.equals(itemId) & t.attributeId.equals(attrs.first.id)))
        .get();
    if (itemAttrs.isEmpty) return null;

    return int.tryParse(itemAttrs.first.value ?? '');
  }

  Future<void> checkAndScheduleExpireReminders(
    AppDatabase db,
    SettingsProvider settingsProvider,
  ) async {
    try {
      if (!settingsProvider.enableExpireNotification) {
        print('[NotificationService] Notifications disabled');
        await cancelAllNotifications();
        return;
      }

      print('[NotificationService] === Starting schedule reminders ===');
      print('[NotificationService] Enabled: true');
      print('[NotificationService] Time: ${settingsProvider.expireNotificationTime.hour}:${settingsProvider.expireNotificationTime.minute}');
      print('[NotificationService] Offsets: ${settingsProvider.expireWarningOffsets}');

      await init();

      final now = DateTime.now();
      final notificationTime = TimeOfDay(
        hour: settingsProvider.expireNotificationTime.hour,
        minute: settingsProvider.expireNotificationTime.minute,
      );

      final houses = await (db.select(db.houses)).get();
      print('[NotificationService] Found ${houses.length} houses');

      int scheduledCount = 0;

      for (final house in houses) {
        final items = await (db.select(db.items)
              ..where((t) =>
                  t.houseId.equals(house.id) &
                  t.expireDate.isNotNull()))
            .get();

        print('[NotificationService] House ${house.id}: ${items.length} items');

        for (final item in items) {
          if (item.expireDate == null) continue;

          print('[NotificationService] Processing: ${item.name}, expire: ${item.expireDate}');

          final itemOffset = await _getItemExpireReminderOffset(db, item.id);
          final offsets = List<int>.from(settingsProvider.expireWarningOffsets);
          if (itemOffset != null && itemOffset >= 0 && !offsets.contains(itemOffset)) {
            offsets.add(itemOffset);
            offsets.sort();
          }

          for (final offset in offsets) {
            final reminderDate = item.expireDate!.subtract(Duration(days: offset));

            DateTime notificationDateTime = DateTime(
              reminderDate.year,
              reminderDate.month,
              reminderDate.day,
              notificationTime.hour,
              notificationTime.minute,
            );

            print('[NotificationService]   Offset: $offset days -> $notificationDateTime');

            if (notificationDateTime.isBefore(now)) {
              print('[NotificationService]   Skipping (past)');
              continue;
            }

            final notificationId = _generateNotificationId(item.id, offset);
            final isWarranty = item.customAttributes == 'warranty';
            final suffix = isWarranty ? '过保' : '过期';
            final body = offset == 0
                ? '今天$suffix，请及时处理'
                : '将在 $offset 天后$suffix';

            await scheduleExpireNotification(
              notificationId,
              item.name,
              notificationDateTime,
              body,
            );
            scheduledCount++;
          }
        }
      }

      print('[NotificationService] === Scheduled $scheduledCount notifications ===');
    } catch (e, stackTrace) {
      print('[NotificationService] Error scheduling: $e');
      print('[NotificationService] Stack trace: $stackTrace');
    }
  }

  static const String _keyLastImmediateNotificationDate = 'last_immediate_notification_date';

  Future<void> checkAndSendImmediateReminders(
    AppDatabase db,
    SettingsProvider settingsProvider,
  ) async {
    try {
      if (!settingsProvider.enableExpireNotification) {
        print('[NotificationService] Notifications disabled');
        return;
      }

      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final prefs = await SharedPreferences.getInstance();
      final lastSentDate = prefs.getString(_keyLastImmediateNotificationDate);
      if (lastSentDate == todayStr) {
        print('[NotificationService] Already sent immediate notifications today');
        return;
      }

      print('[NotificationService] Checking immediate reminders...');

      final houses = await (db.select(db.houses)).get();
      print('[NotificationService] Found ${houses.length} houses');

      int notificationCount = 0;

      for (final house in houses) {
        final items = await (db.select(db.items)
              ..where((t) =>
                  t.houseId.equals(house.id) &
                  t.expireDate.isNotNull()))
            .get();

        print('[NotificationService] House ${house.id}: ${items.length} items');

        for (final item in items) {
          if (item.expireDate == null) continue;

          final itemOffset = await _getItemExpireReminderOffset(db, item.id);
          final offsets = List<int>.from(settingsProvider.expireWarningOffsets);
          if (itemOffset != null && itemOffset >= 0 && !offsets.contains(itemOffset)) {
            offsets.add(itemOffset);
            offsets.sort();
          }

          for (final offset in offsets) {
            final reminderDate = item.expireDate!.subtract(Duration(days: offset));

            if (_isSameDay(reminderDate, now)) {
              final notificationId = _generateNotificationId(item.id, offset);
              final isWarranty = item.customAttributes == 'warranty';
              final suffix = isWarranty ? '过保' : '过期';
              final body = offset == 0
                  ? '今天$suffix，请及时处理'
                  : '将在 $offset 天后$suffix';

              await showNotification(notificationId, item.name, body);
              notificationCount++;
            }
          }
        }
      }

      if (notificationCount > 0) {
        await prefs.setString(_keyLastImmediateNotificationDate, todayStr);
      }

      print('[NotificationService] Sent $notificationCount immediate notifications');
    } catch (e, stackTrace) {
      print('[NotificationService] Error sending immediate: $e');
      print('[NotificationService] Stack trace: $stackTrace');
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  int _generateNotificationId(String itemId, int offset) {
    return itemId.hashCode + offset;
  }
}
