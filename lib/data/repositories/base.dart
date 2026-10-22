import 'package:sqflite/sqflite.dart';

/// Change keys emitted after writes so dependent UI can refresh.
abstract final class Chg {
  static const todo = 'todo';
  static const gym = 'gym';
  static const money = 'money';
  static const reminders = 'reminders';
  static const habits = 'habits';
  static const calendar = 'calendar';
  static const documents = 'documents';
  static const notes = 'notes';
  static const study = 'study';
  static const settings = 'settings';

  static const all = [todo, gym, money, reminders, habits, calendar, documents, notes, study, settings];
}

typedef ChangeSink = void Function(String topic);

abstract class Repo {
  Repo(this.db, this.changed);
  final Database db;
  final ChangeSink changed;

  /// Escapes a user search term for LIKE.
  static String like(String q) => '%${q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';

  static String placeholders(int n) => List.filled(n, '?').join(',');
}
