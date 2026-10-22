import 'package:intl/intl.dart';

/// Money is stored as integer minor units (paise/cents) to avoid float drift.
abstract final class Money {
  static String symbol = '₹';

  static int toMinor(double v) => (v * 100).round();
  static double toMajor(int minor) => minor / 100;

  static String format(int minor, {bool compact = false, bool sign = false}) {
    final v = minor / 100;
    final whole = minor % 100 == 0;
    final String body;
    if (compact && v.abs() >= 100000) {
      body = NumberFormat.compact(locale: 'en_IN').format(v.abs());
    } else {
      body = NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: whole ? 0 : 2).format(v.abs()).trim();
    }
    final prefix = minor < 0 ? '-' : (sign && minor > 0 ? '+' : '');
    return '$prefix$symbol$body';
  }

  /// Parses user input like "1,250.50" → 125050.
  static int? parse(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final v = double.tryParse(cleaned);
    return v == null ? null : toMinor(v);
  }

  static String inputValue(int minor) {
    final v = minor / 100;
    return minor % 100 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }
}

String pct(double ratio) => '${(ratio * 100).round()}%';

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

String trimNum(double v, {int digits = 1}) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(digits);
}
