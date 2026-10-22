import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/dates.dart';
import '../core/utils/format.dart';
import '../data/repositories/document_repo.dart';
import '../state/providers.dart';
import 'notification_service.dart';

/// Computes every notification that should be pending in the next
/// [horizon] from the database. Recurring items are expanded into
/// individual occurrences, so they keep firing after app/phone restarts
/// (the plugin restores scheduled alarms on boot), and the plan is rebuilt
/// whenever data changes or the app is opened.
class NotificationPlanner {
  NotificationPlanner(this.ref, {this.horizon = const Duration(days: 14), this.maxTotal = 400});

  final Ref ref;
  final Duration horizon;
  final int maxTotal;

  Future<List<PlannedNotification>> plan({DateTime? now}) async {
    now ??= DateTime.now();
    final until = now.add(horizon);
    final s = ref.read(settingsProvider);
    final out = <_Draft>[];

    // Todos: at due time, or 9:00 on the due day for date-only todos.
    if (s.notifyOn(NotifChannel.todo.id)) {
      for (final t in await ref.read(todoRepoProvider).dueBetween(D.today(), until)) {
        if (t.completed || !t.remind || t.dueAt == null) continue;
        final at = t.hasTime ? t.dueAt! : DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day, 9);
        out.add(_Draft(at, t.hasTime ? 'Task due now' : 'Task due today', t.title, NotifChannel.todo, 'todo:${t.id}'));
      }
    }

    // Reminders (recurring series expanded).
    if (s.notifyOn(NotifChannel.reminders.id)) {
      for (final (r, at) in await ref.read(reminderRepoProvider).occurrences(now, until)) {
        out.add(_Draft(at, r.title, r.notes.isEmpty ? 'Reminder' : r.notes, NotifChannel.reminders, 'reminders:${r.id}'));
      }
    }

    // Gym routines scheduled on weekdays.
    if (s.notifyOn(NotifChannel.gym.id)) {
      for (final r in await ref.read(gymRepoProvider).routines()) {
        final m = r.remindMinutes;
        if (m == null || r.weekdays.isEmpty) continue;
        for (var d = D.today(); !d.isAfter(until); d = D.addDays(d, 1)) {
          if (!r.weekdays.contains(d.weekday)) continue;
          out.add(
            _Draft(
              DateTime(d.year, d.month, d.day, m ~/ 60, m % 60),
              'Workout today: ${r.name}',
              '${r.items.length} exercises planned',
              NotifChannel.gym,
              'gym:${r.id}:routine',
            ),
          );
        }
      }
    }

    // Habits on their scheduled days; skip days already completed.
    if (s.notifyOn(NotifChannel.habits.id)) {
      for (final h in await ref.read(habitRepoProvider).all()) {
        final m = h.habit.remindMinutes;
        if (m == null) continue;
        for (var d = D.today(); !d.isAfter(until); d = D.addDays(d, 1)) {
          if (!h.habit.scheduledOn(d) || h.doneOn(d)) continue;
          out.add(
            _Draft(DateTime(d.year, d.month, d.day, m ~/ 60, m % 60), h.habit.name, 'Keep your streak going', NotifChannel.habits, 'habits:${h.habit.id}'),
          );
        }
      }
    }

    // Bills & recurring payments: 9:00 on each due date.
    if (s.notifyOn(NotifChannel.bills.id)) {
      for (final r in await ref.read(moneyRepoProvider).recurring()) {
        if (!r.active || !r.remind) continue;
        final dates = r.recurrence.occurrences(r.anchor, r.next.isAfter(D.today()) ? r.next : D.today(), until, max: 30);
        for (final d in dates.where((d) => !d.isBefore(r.next))) {
          final verb = r.kind.index == 0 ? 'due' : 'expected';
          out.add(_Draft(DateTime(d.year, d.month, d.day, 9), '${r.title} $verb today', Money.format(r.amount), NotifChannel.bills, 'money:${r.id}:recurring'));
        }
      }
    }

    // Documents: renewal reminder and expiry day.
    if (s.notifyOn(NotifChannel.documents.id)) {
      for (final doc in await ref.read(documentRepoProvider).all()) {
        final exp = doc.expiryAt;
        if (exp == null) continue;
        final remindAt = doc.remindAt;
        if (remindAt != null) {
          out.add(
            _Draft(
              remindAt,
              '${doc.name} expires in ${doc.remindDays} days',
              'Expiry: ${D.dayMonthYear(exp)}. Time to renew.',
              NotifChannel.documents,
              'documents:${doc.id}',
            ),
          );
        }
        out.add(_Draft(DateTime(exp.year, exp.month, exp.day, 9), '${doc.name} expires today', doc.category, NotifChannel.documents, 'documents:${doc.id}'));
      }
    }

    // Study: daily reminder unless today's target is already met.
    final sm = s.studyReminderMin;
    if (sm != null && s.notifyOn(NotifChannel.study.id)) {
      final studied = await ref.read(studyRepoProvider).secondsBetween(D.today(), D.endOfDay(now));
      for (var d = D.today(); !d.isAfter(until); d = D.addDays(d, 1)) {
        if (D.sameDay(d, now) && studied >= s.studyDailyTargetMin * 60) continue;
        out.add(
          _Draft(
            DateTime(d.year, d.month, d.day, sm ~/ 60, sm % 60),
            'Time to study',
            'Daily target: ${D.duration(Duration(minutes: s.studyDailyTargetMin))}',
            NotifChannel.study,
            'study:0',
          ),
        );
      }
    }

    // Calendar events with a reminder offset.
    if (s.notifyOn(NotifChannel.calendar.id)) {
      final events = await ref.read(eventRepoProvider).occurrences(now, until.add(const Duration(days: 1)));
      for (final (e, start) in events) {
        final before = e.remindBefore;
        if (before == null) continue;
        final base = e.allDay ? DateTime(start.year, start.month, start.day, 9) : start;
        final at = base.subtract(Duration(minutes: before));
        final when = e.allDay ? 'All day, ${D.relativeDay(start)}' : (before == 0 ? 'Starting now' : 'At ${D.time(start)}');
        out.add(_Draft(at, e.title, e.location.isEmpty ? when : '$when · ${e.location}', NotifChannel.calendar, 'calendar:${e.id}'));
      }
    }

    final future = out.where((d) => d.at.isAfter(now!) && !d.at.isAfter(until)).toList()..sort((a, b) => a.at.compareTo(b.at));
    final capped = future.take(maxTotal).toList();
    return [
      for (var k = 0; k < capped.length; k++)
        PlannedNotification(
          id: NotificationService.plannedBase + k,
          at: capped[k].at,
          title: capped[k].title,
          body: capped[k].body,
          channel: capped[k].channel,
          payload: capped[k].payload,
        ),
    ];
  }
}

class _Draft {
  _Draft(this.at, this.title, this.body, this.channel, this.payload);
  final DateTime at;
  final String title;
  final String body;
  final NotifChannel channel;
  final String payload;
}

/// Debounced re-sync of scheduled notifications whenever data changes.
/// Syncs are serialized so overlapping runs can't interleave cancels and
/// schedules.
class NotificationSync {
  NotificationSync(this.ref);
  final Ref ref;
  Timer? _debounce;
  Future<void>? _running;
  bool _again = false;

  void schedule({Duration delay = const Duration(milliseconds: 1200)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, run);
  }

  Future<void> run() async {
    if (_running != null) {
      _again = true;
      return _running;
    }
    _running = _doRun();
    try {
      await _running;
    } finally {
      _running = null;
    }
    if (_again) {
      _again = false;
      await run();
    }
  }

  Future<void> _doRun() async {
    try {
      final svc = NotificationService.instance;
      if (!svc.supported) return;
      final planned = await NotificationPlanner(ref).plan();
      await svc.replacePlanned(planned);
    } catch (e, st) {
      debugPrint('Notification sync failed: $e\n$st');
    }
  }

  void dispose() => _debounce?.cancel();
}

final notificationSyncProvider = Provider<NotificationSync>((ref) {
  final sync = NotificationSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});
