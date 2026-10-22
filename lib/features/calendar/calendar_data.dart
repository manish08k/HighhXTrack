import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/utils/dates.dart';
import '../../data/repositories/base.dart';
import '../../state/providers.dart';

/// One entry on the unified calendar, from any module.
class CalItem {
  const CalItem({
    required this.module,
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    required this.color,
    this.subtitle = '',
    this.done = false,
    this.kind,
  });
  final AppModule module;
  final int id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final Color color;
  final String subtitle;
  final bool done;

  /// Passed to openItem (e.g. 'workout').
  final String? kind;
}

typedef DayRange = (DateTime, DateTime);

/// Every calendar-visible item in [range], sorted by start.
final calendarItemsProvider = FutureProvider.autoDispose.family<List<CalItem>, DayRange>((ref, range) async {
  ref.watchTopics([Chg.calendar, Chg.todo, Chg.gym, Chg.reminders, Chg.study]);
  final (from, to) = range;
  final out = <CalItem>[];

  for (final (e, start) in await ref.read(eventRepoProvider).occurrences(from, to)) {
    out.add(
      CalItem(
        module: AppModule.calendar,
        id: e.id!,
        title: e.title,
        start: start,
        end: start.add(e.length),
        allDay: e.allDay,
        color: Color(e.color),
        subtitle: [
          if (!e.allDay) '${D.time(start)} – ${D.time(start.add(e.length))}',
          if (e.location.isNotEmpty) e.location,
          if (e.recurrence.repeats) e.recurrence.label,
        ].join(' · '),
      ),
    );
  }
  for (final t in await ref.read(todoRepoProvider).dueBetween(from, to)) {
    out.add(
      CalItem(
        module: AppModule.todo,
        id: t.id!,
        title: t.title,
        start: t.dueAt!,
        allDay: !t.hasTime,
        color: AppModule.todo.color,
        subtitle: t.hasTime ? 'Due ${D.time(t.dueAt!)}' : 'Task due',
        done: t.completed,
      ),
    );
  }
  for (final w in await ref.read(gymRepoProvider).workoutsBetween(from, to)) {
    out.add(
      CalItem(
        module: AppModule.gym,
        id: w.id!,
        title: w.name,
        start: w.startedAt,
        end: w.endedAt ?? DateTime.now(),
        color: AppModule.gym.color,
        subtitle: w.isActive ? 'In progress' : 'Workout · ${D.duration(w.duration)}',
        done: !w.isActive,
        kind: w.isActive ? 'active' : 'workout',
      ),
    );
  }
  for (final (r, at) in await ref.read(reminderRepoProvider).occurrences(from, to)) {
    out.add(CalItem(module: AppModule.reminders, id: r.id!, title: r.title, start: at, color: AppModule.reminders.color, subtitle: 'Reminder · ${D.time(at)}'));
  }
  for (final s in await ref.read(studyRepoProvider).sessionsBetween(from, to)) {
    out.add(
      CalItem(
        module: AppModule.study,
        id: s.subjectId ?? 0,
        title: s.subjectName ?? 'Study session',
        start: s.startedAt,
        end: s.startedAt.add(s.duration),
        color: s.subjectColor == null ? AppModule.study.color : Color(s.subjectColor!),
        subtitle: '${s.topicName ?? 'Study'} · ${D.duration(s.duration)}',
        done: true,
        kind: 'subject',
      ),
    );
  }
  out.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    return a.start.compareTo(b.start);
  });
  return out;
});

/// Range covering the visible month grid (Monday-start, 6 weeks).
DayRange monthGridRange(DateTime month) {
  final start = D.startOfWeek(D.startOfMonth(month));
  return (start, D.endOfDay(D.addDays(start, 41)));
}

DayRange weekRange(DateTime day) {
  final s = D.startOfWeek(day);
  return (s, D.endOfDay(D.addDays(s, 6)));
}

DayRange dayRange(DateTime day) => (D.dateOnly(day), D.endOfDay(day));

/// Items starting on [day] (or spanning it).
List<CalItem> itemsOn(List<CalItem> items, DateTime day) {
  final s = D.dateOnly(day);
  final e = D.endOfDay(day);
  return items.where((i) => !i.start.isAfter(e) && !(i.end ?? i.start).isBefore(s)).toList();
}
