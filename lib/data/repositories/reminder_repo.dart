import 'package:sqflite/sqflite.dart';

import '../../core/utils/dates.dart';
import '../models/planner.dart';
import 'base.dart';

class ReminderUndo {
  ReminderUndo(this.row, this.logId);
  final Map<String, Object?> row;
  final int? logId;
}

class ReminderRepo extends Repo {
  ReminderRepo(super.db, super.changed);

  Future<List<Reminder>> active({String search = ''}) async {
    final rows = await db.query(
      'reminders',
      where: search.isEmpty ? 'completed=0' : "completed=0 AND (title LIKE ? ESCAPE '\\' OR notes LIKE ? ESCAPE '\\')",
      whereArgs: search.isEmpty ? null : [Repo.like(search), Repo.like(search)],
      orderBy: 'due_at ASC',
    );
    return rows.map(Reminder.fromMap).toList();
  }

  Future<List<Reminder>> upcoming({int limit = 5}) async {
    final rows = await db.query('reminders', where: 'completed=0', orderBy: 'due_at ASC', limit: limit);
    return rows.map(Reminder.fromMap).toList();
  }

  Future<Reminder?> get(int id) async {
    final rows = await db.query('reminders', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : Reminder.fromMap(rows.first);
  }

  Future<List<Reminder>> forLink(String module, int id) async {
    final rows = await db.query('reminders', where: 'completed=0 AND link_module=? AND link_id=?', whereArgs: [module, id], orderBy: 'due_at');
    return rows.map(Reminder.fromMap).toList();
  }

  Future<List<ReminderLog>> history({int limit = 200}) async {
    final rows = await db.query('reminder_history', orderBy: 'done_at DESC', limit: limit);
    return rows.map(ReminderLog.fromMap).toList();
  }

  Future<int> save(Reminder r) async {
    final int id;
    if (r.id == null) {
      id = await db.insert('reminders', r.toMap());
    } else {
      id = r.id!;
      await db.update('reminders', r.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.reminders);
    return id;
  }

  /// Completes the current occurrence. Recurring reminders roll forward to
  /// their next future occurrence; one-time reminders move to history.
  Future<ReminderUndo> complete(Reminder r) async {
    final before = (await db.query('reminders', where: 'id=?', whereArgs: [r.id])).first;
    late int logId;
    await db.transaction((tx) async {
      final now = DateTime.now();
      logId = await tx.insert('reminder_history', {'reminder_id': r.id, 'title': r.title, 'due_at': D.ms(r.dueAt), 'done_at': D.ms(now)});
      if (r.recurrence.repeats) {
        var next = r.recurrence.nextAfter(r.anchorAt, r.dueAt);
        while (next != null && next.isBefore(now)) {
          next = r.recurrence.nextAfter(r.anchorAt, next);
        }
        if (next != null) {
          await tx.update('reminders', {'due_at': D.ms(next)}, where: 'id=?', whereArgs: [r.id]);
          return;
        }
      }
      await tx.update('reminders', {'completed': 1, 'completed_at': D.ms(now)}, where: 'id=?', whereArgs: [r.id]);
    });
    changed(Chg.reminders);
    return ReminderUndo(before, logId);
  }

  Future<void> undo(ReminderUndo u) async {
    await db.transaction((tx) async {
      await tx.insert('reminders', u.row, conflictAlgorithm: ConflictAlgorithm.replace);
      if (u.logId != null) await tx.delete('reminder_history', where: 'id=?', whereArgs: [u.logId]);
    });
    changed(Chg.reminders);
  }

  Future<void> snooze(Reminder r, Duration by) async {
    await db.update('reminders', {'due_at': D.ms(DateTime.now().add(by))}, where: 'id=?', whereArgs: [r.id]);
    changed(Chg.reminders);
  }

  /// Moves only the current occurrence; the series anchor is unchanged.
  Future<void> moveTo(Reminder r, DateTime at) async {
    await db.update('reminders', {'due_at': D.ms(at)}, where: 'id=?', whereArgs: [r.id]);
    changed(Chg.reminders);
  }

  Future<ReminderUndo?> delete(int id) async {
    final rows = await db.query('reminders', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    await db.delete('reminders', where: 'id=?', whereArgs: [id]);
    changed(Chg.reminders);
    return ReminderUndo(rows.first, null);
  }

  Future<void> clearHistory() async {
    await db.delete('reminder_history');
    changed(Chg.reminders);
  }

  /// Active reminders occurring in [from, to], expanding recurring series.
  Future<List<(Reminder, DateTime)>> occurrences(DateTime from, DateTime to) async {
    final rows = await db.query('reminders', where: 'completed=0 AND (due_at<=? )', whereArgs: [D.ms(to)]);
    final out = <(Reminder, DateTime)>[];
    for (final r in rows.map(Reminder.fromMap)) {
      if (r.recurrence.repeats) {
        // The current (possibly snoozed) occurrence, then the series after it.
        if (!r.dueAt.isBefore(from) && !r.dueAt.isAfter(to)) out.add((r, r.dueAt));
        final start = r.dueAt.isAfter(from) ? r.dueAt : from;
        for (final d in r.recurrence.occurrences(r.anchorAt, start, to, max: 60)) {
          if (d.isAfter(r.dueAt)) out.add((r, d));
        }
      } else if (!r.dueAt.isBefore(from)) {
        out.add((r, r.dueAt));
      }
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }
}
