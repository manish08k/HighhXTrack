import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'seed.dart';

/// Single SQLite database for the whole app.
///
/// Conventions:
///  * `*_at` columns are local epoch milliseconds.
///  * `day` columns are integer `yyyymmdd` keys.
///  * Money amounts are integer minor units.
///  * Booleans are 0/1 integers.
class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Database db;
  final String path;

  static const fileName = 'highhxtrack.db';
  static const version = 1;

  /// Every table, in dependency order (parents first). Used by backup/restore.
  static const tables = <String>[
    'settings',
    'todo_categories',
    'todos',
    'subtasks',
    'attachments',
    'exercises',
    'routines',
    'routine_exercises',
    'workouts',
    'workout_exercises',
    'workout_sets',
    'body_metrics',
    'money_categories',
    'recurring_transactions',
    'transactions',
    'reminders',
    'reminder_history',
    'habits',
    'habit_logs',
    'events',
    'documents',
    'note_folders',
    'notes',
    'subjects',
    'topics',
    'study_sessions',
  ];

  static Future<AppDatabase> open({String? overridePath, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final path = overridePath ?? p.join(await getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, v) async {
          final batch = db.batch();
          for (final stmt in schema) {
            batch.execute(stmt);
          }
          await batch.commit(noResult: true);
          await Seed.run(db);
        },
        onUpgrade: (db, from, to) async {
          // Future migrations go here, keyed by `from`.
        },
      ),
    );
    return AppDatabase._(db, path);
  }

  Future<void> close() => db.close();

  /// Copies the DB file into app documents/snapshots, keeping the last [keep].
  /// Called on start so a corrupt write can always be recovered.
  Future<void> snapshot({int keep = 3}) async {
    try {
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'snapshots'));
      await dir.create(recursive: true);
      final today = DateTime.now();
      final name = 'snapshot_${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}.db';
      final target = File(p.join(dir.path, name));
      if (!await target.exists()) {
        await File(path).copy(target.path);
      }
      final files = (await dir.list().toList()).whereType<File>().toList()..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(keep)) {
        await f.delete();
      }
    } catch (_) {
      // Snapshotting is best-effort.
    }
  }

  static const schema = <String>[
    '''CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)''',

    // ---------- TODO ----------
    '''CREATE TABLE todo_categories(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      position INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE todos(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      priority INTEGER NOT NULL DEFAULT 1,
      category_id INTEGER REFERENCES todo_categories(id) ON DELETE SET NULL,
      due_at INTEGER,
      has_time INTEGER NOT NULL DEFAULT 0,
      recurrence TEXT NOT NULL DEFAULT '',
      remind INTEGER NOT NULL DEFAULT 1,
      completed INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL)''',
    'CREATE INDEX idx_todos_due ON todos(completed, archived, due_at)',
    '''CREATE TABLE subtasks(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      todo_id INTEGER NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      done INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0)''',
    'CREATE INDEX idx_subtasks_todo ON subtasks(todo_id)',

    // Generic file attachments (todos, documents).
    '''CREATE TABLE attachments(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_type TEXT NOT NULL,
      owner_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      path TEXT NOT NULL,
      size INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL)''',
    'CREATE INDEX idx_attach_owner ON attachments(owner_type, owner_id)',

    // ---------- GYM ----------
    '''CREATE TABLE exercises(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      muscle TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '',
      rest_seconds INTEGER NOT NULL DEFAULT 90,
      is_custom INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0)''',
    'CREATE INDEX idx_ex_muscle ON exercises(muscle)',
    '''CREATE TABLE routines(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      weekdays TEXT NOT NULL DEFAULT '',
      remind_minutes INTEGER,
      color INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE routine_exercises(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      routine_id INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
      exercise_id INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
      sets INTEGER NOT NULL DEFAULT 3,
      reps INTEGER NOT NULL DEFAULT 10,
      position INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE workouts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      routine_id INTEGER REFERENCES routines(id) ON DELETE SET NULL,
      started_at INTEGER NOT NULL,
      ended_at INTEGER,
      notes TEXT NOT NULL DEFAULT '')''',
    'CREATE INDEX idx_workouts_start ON workouts(started_at)',
    '''CREATE TABLE workout_exercises(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
      exercise_id INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
      position INTEGER NOT NULL DEFAULT 0,
      notes TEXT NOT NULL DEFAULT '')''',
    'CREATE INDEX idx_wex_workout ON workout_exercises(workout_id)',
    'CREATE INDEX idx_wex_exercise ON workout_exercises(exercise_id)',
    '''CREATE TABLE workout_sets(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      workout_exercise_id INTEGER NOT NULL REFERENCES workout_exercises(id) ON DELETE CASCADE,
      position INTEGER NOT NULL DEFAULT 0,
      weight REAL NOT NULL DEFAULT 0,
      reps INTEGER NOT NULL DEFAULT 0,
      status INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER)''',
    'CREATE INDEX idx_sets_wex ON workout_sets(workout_exercise_id)',
    '''CREATE TABLE body_metrics(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      value REAL NOT NULL,
      measured_at INTEGER NOT NULL)''',
    'CREATE INDEX idx_body_kind ON body_metrics(kind, measured_at)',

    // ---------- MONEY ----------
    '''CREATE TABLE money_categories(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      kind INTEGER NOT NULL DEFAULT 0,
      icon INTEGER NOT NULL,
      color INTEGER NOT NULL,
      budget INTEGER,
      is_default INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE recurring_transactions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      kind INTEGER NOT NULL DEFAULT 0,
      amount INTEGER NOT NULL,
      category_id INTEGER REFERENCES money_categories(id) ON DELETE SET NULL,
      payment_method TEXT NOT NULL DEFAULT '',
      recurrence TEXT NOT NULL,
      anchor_at INTEGER NOT NULL,
      next_at INTEGER NOT NULL,
      auto_add INTEGER NOT NULL DEFAULT 1,
      remind INTEGER NOT NULL DEFAULT 1,
      active INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE transactions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind INTEGER NOT NULL DEFAULT 0,
      amount INTEGER NOT NULL,
      category_id INTEGER REFERENCES money_categories(id) ON DELETE SET NULL,
      date_at INTEGER NOT NULL,
      payment_method TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      recurring_id INTEGER REFERENCES recurring_transactions(id) ON DELETE SET NULL,
      created_at INTEGER NOT NULL)''',
    'CREATE INDEX idx_tx_date ON transactions(date_at)',
    'CREATE INDEX idx_tx_cat ON transactions(category_id, date_at)',

    // ---------- REMINDERS ----------
    '''CREATE TABLE reminders(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '',
      due_at INTEGER NOT NULL,
      anchor_at INTEGER NOT NULL,
      recurrence TEXT NOT NULL DEFAULT '',
      priority INTEGER NOT NULL DEFAULT 1,
      link_module TEXT,
      link_id INTEGER,
      completed INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      created_at INTEGER NOT NULL)''',
    'CREATE INDEX idx_rem_due ON reminders(completed, due_at)',
    '''CREATE TABLE reminder_history(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reminder_id INTEGER REFERENCES reminders(id) ON DELETE SET NULL,
      title TEXT NOT NULL,
      due_at INTEGER NOT NULL,
      done_at INTEGER NOT NULL)''',

    // ---------- HABITS ----------
    '''CREATE TABLE habits(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      icon INTEGER NOT NULL,
      color INTEGER NOT NULL,
      schedule INTEGER NOT NULL DEFAULT 0,
      weekdays TEXT NOT NULL DEFAULT '',
      weekly_target INTEGER NOT NULL DEFAULT 3,
      remind_minutes INTEGER,
      archived INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL)''',
    '''CREATE TABLE habit_logs(
      habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
      day INTEGER NOT NULL,
      PRIMARY KEY(habit_id, day))''',

    // ---------- CALENDAR ----------
    '''CREATE TABLE events(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '',
      location TEXT NOT NULL DEFAULT '',
      start_at INTEGER NOT NULL,
      end_at INTEGER NOT NULL,
      all_day INTEGER NOT NULL DEFAULT 0,
      color INTEGER NOT NULL,
      recurrence TEXT NOT NULL DEFAULT '',
      remind_before INTEGER,
      created_at INTEGER NOT NULL)''',
    'CREATE INDEX idx_events_start ON events(start_at)',

    // ---------- DOCUMENTS ----------
    '''CREATE TABLE documents(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      number TEXT NOT NULL DEFAULT '',
      issue_at INTEGER,
      expiry_at INTEGER,
      notes TEXT NOT NULL DEFAULT '',
      remind_days INTEGER NOT NULL DEFAULT 30,
      created_at INTEGER NOT NULL)''',

    // ---------- NOTES ----------
    '''CREATE TABLE note_folders(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE notes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL DEFAULT '',
      body TEXT NOT NULL DEFAULT '',
      checklist TEXT NOT NULL DEFAULT '',
      folder_id INTEGER REFERENCES note_folders(id) ON DELETE SET NULL,
      tags TEXT NOT NULL DEFAULT '',
      pinned INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL)''',
    'CREATE INDEX idx_notes_upd ON notes(archived, pinned, updated_at)',

    // ---------- STUDY ----------
    '''CREATE TABLE subjects(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      archived INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL)''',
    '''CREATE TABLE topics(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '',
      done INTEGER NOT NULL DEFAULT 0,
      done_at INTEGER,
      position INTEGER NOT NULL DEFAULT 0)''',
    'CREATE INDEX idx_topics_subject ON topics(subject_id)',
    '''CREATE TABLE study_sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id INTEGER REFERENCES subjects(id) ON DELETE CASCADE,
      topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL,
      started_at INTEGER NOT NULL,
      duration_sec INTEGER NOT NULL,
      kind TEXT NOT NULL DEFAULT 'timer',
      notes TEXT NOT NULL DEFAULT '')''',
    'CREATE INDEX idx_study_start ON study_sessions(started_at)',
  ];
}
