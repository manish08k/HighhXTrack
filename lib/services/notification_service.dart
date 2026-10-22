import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notification channels, one per category so users can tune them in
/// Android system settings too.
enum NotifChannel {
  todo('todo', 'Todo deadlines'),
  reminders('reminders', 'Reminders'),
  gym('gym', 'Workout reminders'),
  habits('habits', 'Habit reminders'),
  bills('bills', 'Bills & payments'),
  documents('documents', 'Document expiry'),
  study('study', 'Study reminders'),
  calendar('calendar', 'Calendar events'),
  timers('timers', 'Timers');

  const NotifChannel(this.id, this.label);
  final String id;
  final String label;
}

class PlannedNotification {
  const PlannedNotification({required this.id, required this.at, required this.title, required this.body, required this.channel, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final NotifChannel channel;

  /// `module:id[:kind]` used to open the right screen on tap.
  final String payload;
}

/// Thin wrapper over flutter_local_notifications.
///
/// Scheduled notifications are fully re-synced from the database
/// (see NotificationPlanner) so recurring items stay correct.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = fln.FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _exact = false;

  /// Payloads from tapped notifications.
  final taps = StreamController<String>.broadcast();
  String? launchPayload;

  /// Ids at or above this are owned by the sync planner; below are timers.
  static const plannedBase = 1000;
  static const restTimerId = 1;
  static const pomodoroId = 2;
  static const timerOngoingId = 3;

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<void> init() async {
    if (!supported || _ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    const settings = fln.InitializationSettings(
      android: fln.AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: fln.DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      macOS: fln.DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null && r.payload!.isNotEmpty) taps.add(r.payload!);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      launchPayload = launch!.notificationResponse?.payload;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      for (final c in NotifChannel.values) {
        await android.createNotificationChannel(fln.AndroidNotificationChannel(c.id, c.label, importance: fln.Importance.high));
      }
      _exact = await android.canScheduleExactNotifications() ?? false;
    }
    _ready = true;
  }

  Future<bool> requestPermissions() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final ok = await android.requestNotificationsPermission() ?? false;
      _exact = await android.canScheduleExactNotifications() ?? false;
      return ok;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<fln.IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    return false;
  }

  Future<bool> get exactAlarmsAllowed async {
    final android = _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    _exact = await android.canScheduleExactNotifications() ?? false;
    return _exact;
  }

  Future<void> requestExactAlarms() async {
    final android = _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
    _exact = await android?.canScheduleExactNotifications() ?? false;
  }

  Future<bool> get enabled async {
    final android = _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.areNotificationsEnabled() ?? false;
  }

  fln.NotificationDetails _details(NotifChannel c, {bool ongoing = false, bool silent = false, DateTime? countdownTo}) => fln.NotificationDetails(
    android: fln.AndroidNotificationDetails(
      c.id,
      c.label,
      importance: fln.Importance.high,
      priority: fln.Priority.high,
      color: const Color(0xFF4F5BD5),
      ongoing: ongoing,
      silent: silent,
      autoCancel: !ongoing,
      usesChronometer: countdownTo != null,
      chronometerCountDown: countdownTo != null,
      when: countdownTo?.millisecondsSinceEpoch,
      category: c == NotifChannel.timers ? fln.AndroidNotificationCategory.alarm : fln.AndroidNotificationCategory.reminder,
    ),
    iOS: const fln.DarwinNotificationDetails(),
    macOS: const fln.DarwinNotificationDetails(),
  );

  Future<void> schedule(PlannedNotification n) async {
    if (!_ready) return;
    if (!n.at.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: tz.TZDateTime.from(n.at, tz.local),
        notificationDetails: _details(n.channel),
        androidScheduleMode: _exact ? fln.AndroidScheduleMode.exactAllowWhileIdle : fln.AndroidScheduleMode.inexactAllowWhileIdle,
        payload: n.payload,
      );
    } catch (e) {
      debugPrint('schedule failed: $e');
    }
  }

  Future<void> showNow({required int id, required String title, required String body, NotifChannel channel = NotifChannel.timers, String? payload}) async {
    if (!_ready) return;
    await _plugin.show(id: id, title: title, body: body, notificationDetails: _details(channel), payload: payload);
  }

  /// Persistent "timer running" notification with a live countdown.
  Future<void> showOngoingTimer({required String title, required String body, DateTime? endsAt, String? payload}) async {
    if (!_ready) return;
    await _plugin.show(
      id: timerOngoingId,
      title: title,
      body: body,
      notificationDetails: _details(NotifChannel.timers, ongoing: true, silent: true, countdownTo: endsAt),
      payload: payload,
    );
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  /// Replaces every planner-owned scheduled notification with [planned].
  Future<void> replacePlanned(List<PlannedNotification> planned) async {
    if (!_ready) return;
    final pending = await _plugin.pendingNotificationRequests();
    final wanted = {for (final p in planned) p.id: p};
    for (final p in pending) {
      if (p.id >= plannedBase) await _plugin.cancel(id: p.id);
    }
    for (final p in wanted.values) {
      await schedule(p);
    }
  }

  Future<int> pendingCount() async => _ready ? (await _plugin.pendingNotificationRequests()).length : 0;
}
