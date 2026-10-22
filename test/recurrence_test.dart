import 'package:flutter_test/flutter_test.dart';
import 'package:newone/core/utils/dates.dart';
import 'package:newone/core/utils/recurrence.dart';

void main() {
  group('Recurrence encoding', () {
    test('round-trips', () {
      const r = Recurrence(RepeatFreq.weekly, interval: 2, weekdays: {1, 3, 5});
      expect(Recurrence.decode(r.encode()), r);
      expect(Recurrence.decode(''), Recurrence.none);
      expect(Recurrence.decode('garbage'), Recurrence.none);
    });

    test('labels', () {
      expect(Recurrence.daily.label, 'Daily');
      expect(const Recurrence(RepeatFreq.weekly, weekdays: {1, 2, 3, 4, 5}).label, 'Every weekday');
      expect(const Recurrence(RepeatFreq.daily, interval: 3).label, 'Every 3 days');
    });
  });

  group('occurrences', () {
    final anchor = DateTime(2026, 1, 31, 9, 30);

    test('daily with interval', () {
      const r = Recurrence(RepeatFreq.daily, interval: 2);
      final list = r.occurrences(anchor, DateTime(2026, 2, 1), DateTime(2026, 2, 8, 23));
      expect(list, [DateTime(2026, 2, 2, 9, 30), DateTime(2026, 2, 4, 9, 30), DateTime(2026, 2, 6, 9, 30), DateTime(2026, 2, 8, 9, 30)]);
    });

    test('monthly clamps to month end and keeps preferred day', () {
      final list = Recurrence.monthly.occurrences(anchor, anchor, DateTime(2026, 4, 30, 23));
      expect(list, [DateTime(2026, 1, 31, 9, 30), DateTime(2026, 2, 28, 9, 30), DateTime(2026, 3, 31, 9, 30), DateTime(2026, 4, 30, 9, 30)]);
    });

    test('weekly on multiple weekdays', () {
      // 2026-10-05 is a Monday.
      final a = DateTime(2026, 10, 5, 18);
      const r = Recurrence(RepeatFreq.weekly, weekdays: {1, 3});
      final list = r.occurrences(a, a, DateTime(2026, 10, 19, 23));
      expect(list.map((d) => d.day), [5, 7, 12, 14, 19]);
      expect(list.every((d) => d.hour == 18), isTrue);
    });

    test('every 2 weeks skips alternate weeks', () {
      final a = DateTime(2026, 10, 5, 8);
      const r = Recurrence(RepeatFreq.weekly, interval: 2, weekdays: {1});
      final list = r.occurrences(a, DateTime(2026, 10, 6), DateTime(2026, 11, 30, 23));
      expect(list.map(D.dayMonth), ['19 Oct', '2 Nov', '16 Nov', '30 Nov']);
    });

    test('yearly handles leap day', () {
      final a = DateTime(2024, 2, 29, 10);
      final list = Recurrence.yearly.occurrences(a, a, DateTime(2028, 3, 1));
      expect(list, [DateTime(2024, 2, 29, 10), DateTime(2025, 2, 28, 10), DateTime(2026, 2, 28, 10), DateTime(2027, 2, 28, 10), DateTime(2028, 2, 29, 10)]);
    });

    test('nextAfter is strictly after', () {
      final a = DateTime(2026, 10, 8, 9);
      expect(Recurrence.daily.nextAfter(a, a), DateTime(2026, 10, 9, 9));
      expect(Recurrence.none.nextAfter(a, a), isNull);
      expect(Recurrence.monthly.nextAfter(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), DateTime(2026, 3, 31));
    });

    test('far-future range is efficient and correct', () {
      final a = DateTime(2020, 1, 1, 7);
      final list = Recurrence.daily.occurrences(a, DateTime(2030, 6, 1), DateTime(2030, 6, 3, 23));
      expect(list.length, 3);
      expect(list.first, DateTime(2030, 6, 1, 7));
    });
  });

  group('dates', () {
    test('addMonths clamps', () {
      expect(D.addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(D.addMonths(DateTime(2026, 12, 15), 1), DateTime(2027, 1, 15));
      expect(D.addMonths(DateTime(2026, 1, 15), -1), DateTime(2025, 12, 15));
    });

    test('day keys round-trip', () {
      final d = DateTime(2026, 10, 8);
      expect(D.fromDayKey(D.dayKey(d)), d);
    });

    test('clock and duration formatting', () {
      expect(D.clock(const Duration(seconds: 75)), '01:15');
      expect(D.clock(const Duration(hours: 1, seconds: 5)), '1:00:05');
      expect(D.duration(const Duration(hours: 2, minutes: 15)), '2h 15m');
      expect(D.duration(const Duration(minutes: 45)), '45m');
    });
  });
}
