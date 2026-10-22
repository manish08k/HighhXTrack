import 'package:intl/intl.dart';

/// Date helpers. All persisted timestamps are local-time milliseconds since
/// epoch; day-granular data uses an integer key `yyyymmdd`.
abstract final class D {
  static DateTime now() => DateTime.now();
  static DateTime today() => dateOnly(DateTime.now());

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second, d.millisecond);

  /// Monday-based week start.
  static DateTime startOfWeek(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));
  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);
  static DateTime startOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1);
  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// Adds months, clamping the day so 31 Jan + 1 month = 28/29 Feb.
  static DateTime addMonths(DateTime d, int months, {int? preferredDay}) {
    // Floor division so negative offsets cross year boundaries correctly.
    final y = d.year + ((d.month - 1 + months) / 12).floor();
    final m = (d.month - 1 + months) % 12 + 1;
    final day = (preferredDay ?? d.day).clamp(1, daysInMonth(y, m));
    return DateTime(y, m, day, d.hour, d.minute, d.second);
  }

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  static DateTime fromDayKey(int k) => DateTime(k ~/ 10000, (k ~/ 100) % 100, k % 100);

  static int ms(DateTime d) => d.millisecondsSinceEpoch;
  static DateTime fromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);
  static DateTime? fromMsN(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  static int diffDays(DateTime from, DateTime to) => DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  // ---- Formatting ----
  static String time(DateTime d) => DateFormat.jm().format(d);
  static String dayMonth(DateTime d) => DateFormat('d MMM').format(d);
  static String dayMonthYear(DateTime d) => DateFormat('d MMM yyyy').format(d);
  static String weekdayDayMonth(DateTime d) => DateFormat('EEE, d MMM').format(d);
  static String longDate(DateTime d) => DateFormat('EEEE, d MMMM').format(d);
  static String monthYear(DateTime d) => DateFormat('MMMM yyyy').format(d);
  static String shortMonth(DateTime d) => DateFormat('MMM').format(d);
  static String weekdayShort(DateTime d) => DateFormat('EEE').format(d);
  static String weekdayLetter(int weekday) => const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];
  static String weekdayName(int weekday) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  /// "Today", "Tomorrow", "Yesterday", "Mon, 3 Oct" (+ year if not current).
  static String relativeDay(DateTime d) {
    final diff = diffDays(today(), d);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (d.year != DateTime.now().year) return dayMonthYear(d);
    return weekdayDayMonth(d);
  }

  static String relativeDateTime(DateTime d, {bool hasTime = true}) => hasTime ? '${relativeDay(d)}, ${time(d)}' : relativeDay(d);

  /// "2h 15m", "45m", "0m".
  static String duration(Duration d, {bool seconds = false}) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (seconds && h == 0 && m == 0) return '${s}s';
    if (h == 0) return seconds && s > 0 ? '${m}m ${s}s' : '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// "01:23" or "1:02:03" clock format.
  static String clock(Duration d) {
    final neg = d.isNegative;
    d = d.abs();
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '${neg ? '-' : ''}${h > 0 ? '$h:' : ''}$m:$s';
  }

  static String minutesOfDayLabel(int minutes) => time(DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60));
}
