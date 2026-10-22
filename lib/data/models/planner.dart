import 'dart:ui';

import '../../core/modules.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/recurrence.dart';
import 'common.dart';

// ---------------------------------------------------------------- Reminders

class Reminder {
  const Reminder({
    this.id,
    required this.title,
    this.notes = '',
    required this.dueAt,
    DateTime? anchorAt,
    this.recurrence = Recurrence.none,
    this.priority = Priority.medium,
    this.linkModule,
    this.linkId,
    this.completed = false,
    this.completedAt,
    required this.createdAt,
  }) : anchorAt = anchorAt ?? dueAt;

  final int? id;
  final String title;
  final String notes;

  /// Next due occurrence.
  final DateTime dueAt;

  /// First occurrence of the series (keeps day-of-month stable).
  final DateTime anchorAt;
  final Recurrence recurrence;
  final Priority priority;
  final AppModule? linkModule;
  final int? linkId;
  final bool completed;
  final DateTime? completedAt;
  final DateTime createdAt;

  bool get isOverdue => !completed && dueAt.isBefore(DateTime.now());

  factory Reminder.fromMap(Map<String, Object?> m) => Reminder(
    id: m['id'] as int,
    title: m['title'] as String,
    notes: m['notes'] as String? ?? '',
    dueAt: D.fromMs(m['due_at'] as int),
    anchorAt: D.fromMs(m['anchor_at'] as int),
    recurrence: Recurrence.decode(m['recurrence'] as String?),
    priority: Priority.fromIndex(m['priority'] as int?),
    linkModule: AppModule.byName(m['link_module'] as String?),
    linkId: m['link_id'] as int?,
    completed: b(m['completed']),
    completedAt: D.fromMsN(m['completed_at'] as int?),
    createdAt: D.fromMs(m['created_at'] as int),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'notes': notes,
    'due_at': D.ms(dueAt),
    'anchor_at': D.ms(anchorAt),
    'recurrence': recurrence.encode(),
    'priority': priority.index,
    'link_module': linkModule?.name,
    'link_id': linkId,
    'completed': i(completed),
    'completed_at': completedAt == null ? null : D.ms(completedAt!),
    'created_at': D.ms(createdAt),
  };
}

class ReminderLog {
  const ReminderLog({required this.id, this.reminderId, required this.title, required this.dueAt, required this.doneAt});
  final int id;
  final int? reminderId;
  final String title;
  final DateTime dueAt;
  final DateTime doneAt;

  factory ReminderLog.fromMap(Map<String, Object?> m) => ReminderLog(
    id: m['id'] as int,
    reminderId: m['reminder_id'] as int?,
    title: m['title'] as String,
    dueAt: D.fromMs(m['due_at'] as int),
    doneAt: D.fromMs(m['done_at'] as int),
  );
}

// ---------------------------------------------------------------- Habits

enum HabitSchedule {
  daily('Every day'),
  weekdays('Specific days'),
  weekly('Times per week');

  const HabitSchedule(this.label);
  final String label;
}

class Habit {
  const Habit({
    this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.schedule = HabitSchedule.daily,
    this.weekdays = const {},
    this.weeklyTarget = 3,
    this.remindMinutes,
    this.archived = false,
    this.position = 0,
    required this.createdAt,
  });
  final int? id;
  final String name;
  final int icon;
  final int color;
  final HabitSchedule schedule;
  final Set<int> weekdays;
  final int weeklyTarget;
  final int? remindMinutes;
  final bool archived;
  final int position;
  final DateTime createdAt;

  Color get colorValue => Color(color);

  /// Whether the habit is expected on [d]. Weekly-target habits are
  /// "due" every day until the weekly target is met.
  bool scheduledOn(DateTime d) => switch (schedule) {
    HabitSchedule.daily => true,
    HabitSchedule.weekdays => weekdays.contains(d.weekday),
    HabitSchedule.weekly => true,
  };

  String get scheduleLabel => switch (schedule) {
    HabitSchedule.daily => 'Every day',
    HabitSchedule.weekdays => (weekdays.toList()..sort()).map(D.weekdayName).join(', '),
    HabitSchedule.weekly => '$weeklyTarget× per week',
  };

  factory Habit.fromMap(Map<String, Object?> m) => Habit(
    id: m['id'] as int,
    name: m['name'] as String,
    icon: m['icon'] as int,
    color: m['color'] as int,
    schedule: HabitSchedule.values[(m['schedule'] as int? ?? 0).clamp(0, 2)],
    weekdays: (m['weekdays'] as String? ?? '').isEmpty ? <int>{} : (m['weekdays'] as String).split(',').map(int.parse).toSet(),
    weeklyTarget: m['weekly_target'] as int? ?? 3,
    remindMinutes: m['remind_minutes'] as int?,
    archived: b(m['archived']),
    position: m['position'] as int? ?? 0,
    createdAt: D.fromMs(m['created_at'] as int),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'schedule': schedule.index,
    'weekdays': (weekdays.toList()..sort()).join(','),
    'weekly_target': weeklyTarget,
    'remind_minutes': remindMinutes,
    'archived': i(archived),
    'position': position,
    'created_at': D.ms(createdAt),
  };
}

/// Habit plus its completion log and derived stats.
class HabitStats {
  HabitStats(this.habit, this.days) {
    _compute();
  }

  final Habit habit;

  /// Completed day keys.
  final Set<int> days;

  int currentStreak = 0;
  int bestStreak = 0;
  double weekRate = 0;
  double monthRate = 0;
  int doneThisWeek = 0;

  bool doneOn(DateTime d) => days.contains(D.dayKey(d));
  bool get doneToday => doneOn(DateTime.now());

  void _compute() {
    final today = D.today();
    final created = D.dateOnly(habit.createdAt);
    if (habit.schedule == HabitSchedule.weekly) {
      _computeWeekly(today, created);
    } else {
      _computeDaily(today, created);
    }
    doneThisWeek = 0;
    final ws = D.startOfWeek(today);
    for (var k = 0; k < 7; k++) {
      if (doneOn(D.addDays(ws, k))) doneThisWeek++;
    }
  }

  void _computeDaily(DateTime today, DateTime created) {
    // Current streak: walk back over scheduled days; today not yet done
    // does not break the streak.
    var d = today;
    var streak = 0;
    var first = true;
    for (var guard = 0; guard < 3660; guard++) {
      if (d.isBefore(created) && !doneOn(d)) break;
      if (habit.scheduledOn(d)) {
        if (doneOn(d)) {
          streak++;
        } else if (!first) {
          break;
        }
      }
      first = false;
      d = D.addDays(d, -1);
    }
    currentStreak = streak;

    // Best streak over full history.
    if (days.isNotEmpty) {
      final sorted = days.toList()..sort();
      var cur = 0;
      var best = 0;
      var day = D.fromDayKey(sorted.first);
      while (!day.isAfter(today)) {
        if (habit.scheduledOn(day)) {
          if (doneOn(day)) {
            cur++;
            if (cur > best) best = cur;
          } else if (!D.sameDay(day, today)) {
            cur = 0;
          }
        }
        day = D.addDays(day, 1);
      }
      bestStreak = best;
    }
    weekRate = _rate(today, 7, created);
    monthRate = _rate(today, 30, created);
  }

  double _rate(DateTime today, int window, DateTime created) {
    var expected = 0;
    var done = 0;
    for (var k = 0; k < window; k++) {
      final d = D.addDays(today, -k);
      if (d.isBefore(created)) break;
      if (habit.scheduledOn(d)) {
        expected++;
        if (doneOn(d)) done++;
      }
    }
    return expected == 0 ? 0 : done / expected;
  }

  void _computeWeekly(DateTime today, DateTime created) {
    // Streak counted in weeks meeting the target.
    int countWeek(DateTime ws) {
      var c = 0;
      for (var k = 0; k < 7; k++) {
        if (doneOn(D.addDays(ws, k))) c++;
      }
      return c;
    }

    var ws = D.startOfWeek(today);
    var streak = 0;
    var first = true;
    for (var guard = 0; guard < 520; guard++) {
      final met = countWeek(ws) >= habit.weeklyTarget;
      if (met) {
        streak++;
      } else if (!first) {
        break;
      }
      first = false;
      ws = D.addDays(ws, -7);
      if (ws.isBefore(D.startOfWeek(created))) break;
    }
    currentStreak = streak;
    var best = 0;
    var cur = 0;
    if (days.isNotEmpty) {
      var w = D.startOfWeek(D.fromDayKey(days.reduce((a, b) => a < b ? a : b)));
      while (!w.isAfter(today)) {
        if (countWeek(w) >= habit.weeklyTarget) {
          cur++;
          if (cur > best) best = cur;
        } else if (!D.sameDay(w, D.startOfWeek(today))) {
          cur = 0;
        }
        w = D.addDays(w, 7);
      }
    }
    bestStreak = best;
    weekRate = (countWeek(D.startOfWeek(today)) / habit.weeklyTarget).clamp(0, 1).toDouble();
    var met = 0;
    for (var k = 0; k < 4; k++) {
      final c = countWeek(D.addDays(D.startOfWeek(today), -7 * k));
      met += c >= habit.weeklyTarget ? habit.weeklyTarget : c;
    }
    monthRate = met / (habit.weeklyTarget * 4);
  }
}

// ---------------------------------------------------------------- Calendar

class CalEvent {
  const CalEvent({
    this.id,
    required this.title,
    this.notes = '',
    this.location = '',
    required this.start,
    required this.end,
    this.allDay = false,
    required this.color,
    this.recurrence = Recurrence.none,
    this.remindBefore,
    required this.createdAt,
  });
  final int? id;
  final String title;
  final String notes;
  final String location;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final int color;
  final Recurrence recurrence;

  /// Minutes before start, null = no reminder.
  final int? remindBefore;
  final DateTime createdAt;

  Duration get length => end.difference(start);

  factory CalEvent.fromMap(Map<String, Object?> m) => CalEvent(
    id: m['id'] as int,
    title: m['title'] as String,
    notes: m['notes'] as String? ?? '',
    location: m['location'] as String? ?? '',
    start: D.fromMs(m['start_at'] as int),
    end: D.fromMs(m['end_at'] as int),
    allDay: b(m['all_day']),
    color: m['color'] as int,
    recurrence: Recurrence.decode(m['recurrence'] as String?),
    remindBefore: m['remind_before'] as int?,
    createdAt: D.fromMs(m['created_at'] as int),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'notes': notes,
    'location': location,
    'start_at': D.ms(start),
    'end_at': D.ms(end),
    'all_day': i(allDay),
    'color': color,
    'recurrence': recurrence.encode(),
    'remind_before': remindBefore,
    'created_at': D.ms(createdAt),
  };
}

// ---------------------------------------------------------------- Documents

const kDocCategories = ['Passport', 'Driving License', 'Vehicle Insurance', 'Health Insurance', 'Certificates', 'ID documents', 'Other'];

enum DocStatus {
  valid('Valid', Palette.success),
  expiring('Expiring soon', Palette.warning),
  expired('Expired', Palette.danger),
  noExpiry('No expiry', Color(0xFF8A94A6));

  const DocStatus(this.label, this.color);
  final String label;
  final Color color;
}

class Doc {
  const Doc({
    this.id,
    required this.name,
    required this.category,
    this.number = '',
    this.issueAt,
    this.expiryAt,
    this.notes = '',
    this.remindDays = 30,
    required this.createdAt,
    this.attachmentCount = 0,
  });
  final int? id;
  final String name;
  final String category;
  final String number;
  final DateTime? issueAt;
  final DateTime? expiryAt;
  final String notes;
  final int remindDays;
  final DateTime createdAt;
  final int attachmentCount;

  int? get daysLeft => expiryAt == null ? null : D.diffDays(D.today(), expiryAt!);

  DocStatus get status {
    final d = daysLeft;
    if (d == null) return DocStatus.noExpiry;
    if (d < 0) return DocStatus.expired;
    if (d <= (remindDays < 30 ? 30 : remindDays)) return DocStatus.expiring;
    return DocStatus.valid;
  }

  factory Doc.fromMap(Map<String, Object?> m, {int attachments = 0}) => Doc(
    id: m['id'] as int,
    name: m['name'] as String,
    category: m['category'] as String,
    number: m['number'] as String? ?? '',
    issueAt: D.fromMsN(m['issue_at'] as int?),
    expiryAt: D.fromMsN(m['expiry_at'] as int?),
    notes: m['notes'] as String? ?? '',
    remindDays: m['remind_days'] as int? ?? 30,
    createdAt: D.fromMs(m['created_at'] as int),
    attachmentCount: attachments,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'category': category,
    'number': number,
    'issue_at': issueAt == null ? null : D.ms(issueAt!),
    'expiry_at': expiryAt == null ? null : D.ms(expiryAt!),
    'notes': notes,
    'remind_days': remindDays,
    'created_at': D.ms(createdAt),
  };
}
