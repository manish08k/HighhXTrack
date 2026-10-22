import 'dates.dart';

enum RepeatFreq { none, daily, weekly, monthly, yearly }

/// A compact recurrence rule shared by todos, reminders, events and
/// recurring transactions.
///
/// Encoded as `freq;interval;weekdays` e.g. `weekly;1;1,3,5`.
class Recurrence {
  const Recurrence(this.freq, {this.interval = 1, this.weekdays = const {}});

  static const none = Recurrence(RepeatFreq.none);
  static const daily = Recurrence(RepeatFreq.daily);
  static const weekly = Recurrence(RepeatFreq.weekly);
  static const monthly = Recurrence(RepeatFreq.monthly);
  static const yearly = Recurrence(RepeatFreq.yearly);

  final RepeatFreq freq;
  final int interval;

  /// ISO weekdays (1 = Mon … 7 = Sun); only used for weekly rules.
  final Set<int> weekdays;

  bool get isNone => freq == RepeatFreq.none;
  bool get repeats => freq != RepeatFreq.none;

  bool get isCustom => repeats && (interval > 1 || (freq == RepeatFreq.weekly && weekdays.length > 1));

  String encode() => isNone ? '' : '${freq.name};$interval;${(weekdays.toList()..sort()).join(',')}';

  static Recurrence decode(String? s) {
    if (s == null || s.isEmpty) return none;
    final parts = s.split(';');
    final freq = RepeatFreq.values.firstWhere((f) => f.name == parts[0], orElse: () => RepeatFreq.none);
    final interval = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1).clamp(1, 999) : 1;
    final wd = parts.length > 2 && parts[2].isNotEmpty ? parts[2].split(',').map(int.parse).where((d) => d >= 1 && d <= 7).toSet() : <int>{};
    return Recurrence(freq, interval: interval, weekdays: wd);
  }

  String get label {
    switch (freq) {
      case RepeatFreq.none:
        return 'Does not repeat';
      case RepeatFreq.daily:
        return interval == 1 ? 'Daily' : 'Every $interval days';
      case RepeatFreq.weekly:
        final days = weekdays.isEmpty ? '' : ' on ${(weekdays.toList()..sort()).map(D.weekdayName).join(', ')}';
        if (weekdays.length == 5 && !weekdays.contains(6) && !weekdays.contains(7) && interval == 1) {
          return 'Every weekday';
        }
        return (interval == 1 ? 'Weekly' : 'Every $interval weeks') + days;
      case RepeatFreq.monthly:
        return interval == 1 ? 'Monthly' : 'Every $interval months';
      case RepeatFreq.yearly:
        return interval == 1 ? 'Yearly' : 'Every $interval years';
    }
  }

  /// Occurrences of a series anchored at [anchor] that fall within
  /// [from, to] (inclusive). The time of day is taken from [anchor].
  List<DateTime> occurrences(DateTime anchor, DateTime from, DateTime to, {int max = 500}) {
    final out = <DateTime>[];
    if (to.isBefore(anchor)) return out;
    if (isNone) {
      if (!anchor.isBefore(from) && !anchor.isAfter(to)) out.add(anchor);
      return out;
    }
    final start = from.isBefore(anchor) ? anchor : from;

    switch (freq) {
      case RepeatFreq.none:
        break;
      case RepeatFreq.daily:
        final gap = D.diffDays(anchor, start);
        var k = gap <= 0 ? 0 : (gap ~/ interval);
        while (out.length < max) {
          final d = D.addDays(anchor, k * interval);
          if (d.isAfter(to)) break;
          if (!d.isBefore(start)) out.add(d);
          k++;
        }
      case RepeatFreq.weekly:
        final days = weekdays.isEmpty ? {anchor.weekday} : weekdays;
        final sorted = days.toList()..sort();
        final anchorWeek = D.startOfWeek(anchor);
        final gapWeeks = D.diffDays(anchorWeek, D.startOfWeek(start)) ~/ 7;
        var w = gapWeeks <= 0 ? 0 : (gapWeeks ~/ interval) * interval;
        while (out.length < max) {
          final weekStart = D.addDays(anchorWeek, w * 7);
          if (weekStart.isAfter(to)) break;
          for (final wd in sorted) {
            final day = D.addDays(weekStart, wd - 1);
            final d = DateTime(day.year, day.month, day.day, anchor.hour, anchor.minute);
            if (d.isBefore(anchor) || d.isBefore(start)) continue;
            if (d.isAfter(to)) break;
            out.add(d);
            if (out.length >= max) break;
          }
          w += interval;
        }
      case RepeatFreq.monthly:
      case RepeatFreq.yearly:
        final step = freq == RepeatFreq.monthly ? interval : interval * 12;
        final gapMonths = (start.year - anchor.year) * 12 + start.month - anchor.month;
        var k = gapMonths <= 0 ? 0 : (gapMonths ~/ step) - 1;
        if (k < 0) k = 0;
        while (out.length < max) {
          final d = D.addMonths(anchor, k * step, preferredDay: anchor.day);
          if (d.isAfter(to)) break;
          if (!d.isBefore(start)) out.add(d);
          k++;
        }
    }
    return out;
  }

  /// The first occurrence strictly after [after].
  DateTime? nextAfter(DateTime anchor, DateTime after) {
    if (isNone) return anchor.isAfter(after) ? anchor : null;
    final from = after.add(const Duration(milliseconds: 1));
    final horizon = DateTime(from.year + 2 + (freq == RepeatFreq.yearly ? interval : 0), from.month, from.day + 1);
    final list = occurrences(anchor, from, horizon, max: 1);
    return list.isEmpty ? null : list.first;
  }

  @override
  bool operator ==(Object other) => other is Recurrence && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
