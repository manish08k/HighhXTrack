import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'base.dart';

/// Non-sensitive preferences stored in the database (so they are included
/// in backups). PIN/lock secrets live in secure storage instead.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.currency = '₹',
    this.monthlyBudget,
    this.studyDailyTargetMin = 120,
    this.studyWeeklyTargetMin = 600,
    this.studyReminderMin,
    this.defaultRestSec = 90,
    this.notify = const {},
    this.hideAmounts = false,
    this.secureScreen = false,
    this.lockTimeoutSec = 0,
    this.pomodoroWork = 25,
    this.pomodoroBreak = 5,
    this.weightUnit = 'kg',
  });

  final ThemeMode themeMode;
  final String currency;
  final int? monthlyBudget;
  final int studyDailyTargetMin;
  final int studyWeeklyTargetMin;
  final int? studyReminderMin;
  final int defaultRestSec;

  /// Notification category → enabled. Missing = enabled.
  final Map<String, bool> notify;
  final bool hideAmounts;
  final bool secureScreen;
  final int lockTimeoutSec;
  final int pomodoroWork;
  final int pomodoroBreak;
  final String weightUnit;

  bool notifyOn(String category) => notify[category] ?? true;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? currency,
    int? monthlyBudget,
    bool clearBudget = false,
    int? studyDailyTargetMin,
    int? studyWeeklyTargetMin,
    int? studyReminderMin,
    bool clearStudyReminder = false,
    int? defaultRestSec,
    Map<String, bool>? notify,
    bool? hideAmounts,
    bool? secureScreen,
    int? lockTimeoutSec,
    int? pomodoroWork,
    int? pomodoroBreak,
    String? weightUnit,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    currency: currency ?? this.currency,
    monthlyBudget: clearBudget ? null : (monthlyBudget ?? this.monthlyBudget),
    studyDailyTargetMin: studyDailyTargetMin ?? this.studyDailyTargetMin,
    studyWeeklyTargetMin: studyWeeklyTargetMin ?? this.studyWeeklyTargetMin,
    studyReminderMin: clearStudyReminder ? null : (studyReminderMin ?? this.studyReminderMin),
    defaultRestSec: defaultRestSec ?? this.defaultRestSec,
    notify: notify ?? this.notify,
    hideAmounts: hideAmounts ?? this.hideAmounts,
    secureScreen: secureScreen ?? this.secureScreen,
    lockTimeoutSec: lockTimeoutSec ?? this.lockTimeoutSec,
    pomodoroWork: pomodoroWork ?? this.pomodoroWork,
    pomodoroBreak: pomodoroBreak ?? this.pomodoroBreak,
    weightUnit: weightUnit ?? this.weightUnit,
  );

  Map<String, String?> toKv() => {
    'theme': themeMode.name,
    'currency': currency,
    'monthly_budget': monthlyBudget?.toString(),
    'study_daily': '$studyDailyTargetMin',
    'study_weekly': '$studyWeeklyTargetMin',
    'study_reminder': studyReminderMin?.toString(),
    'rest_default': '$defaultRestSec',
    'notify': notify.entries.map((e) => '${e.key}=${e.value ? 1 : 0}').join(','),
    'hide_amounts': hideAmounts ? '1' : '0',
    'secure_screen': secureScreen ? '1' : '0',
    'lock_timeout': '$lockTimeoutSec',
    'pomo_work': '$pomodoroWork',
    'pomo_break': '$pomodoroBreak',
    'weight_unit': weightUnit,
  };

  factory AppSettings.fromKv(Map<String, String?> kv) {
    int? n(String k) => kv[k] == null ? null : int.tryParse(kv[k]!);
    final notify = <String, bool>{};
    for (final part in (kv['notify'] ?? '').split(',')) {
      final kvp = part.split('=');
      if (kvp.length == 2) notify[kvp[0]] = kvp[1] == '1';
    }
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere((m) => m.name == kv['theme'], orElse: () => ThemeMode.system),
      currency: kv['currency'] ?? '₹',
      monthlyBudget: n('monthly_budget'),
      studyDailyTargetMin: n('study_daily') ?? 120,
      studyWeeklyTargetMin: n('study_weekly') ?? 600,
      studyReminderMin: n('study_reminder'),
      defaultRestSec: n('rest_default') ?? 90,
      notify: notify,
      hideAmounts: kv['hide_amounts'] == '1',
      secureScreen: kv['secure_screen'] == '1',
      lockTimeoutSec: n('lock_timeout') ?? 0,
      pomodoroWork: n('pomo_work') ?? 25,
      pomodoroBreak: n('pomo_break') ?? 5,
      weightUnit: kv['weight_unit'] ?? 'kg',
    );
  }
}

class SettingsRepo extends Repo {
  SettingsRepo(super.db, super.changed);

  Future<AppSettings> load() async {
    final rows = await db.query('settings');
    return AppSettings.fromKv({for (final r in rows) r['key'] as String: r['value'] as String?});
  }

  Future<void> save(AppSettings s) async {
    final b = db.batch();
    for (final e in s.toKv().entries) {
      b.insert('settings', {'key': e.key, 'value': e.value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
    changed(Chg.settings);
  }

  Future<String?> getRaw(String key) async {
    final r = await db.query('settings', where: 'key=?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setRaw(String key, String? value) async {
    await db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
