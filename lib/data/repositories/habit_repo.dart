import '../../core/utils/dates.dart';
import '../models/planner.dart';
import 'base.dart';

class HabitRepo extends Repo {
  HabitRepo(super.db, super.changed);

  Future<List<HabitStats>> all({bool archived = false}) async {
    final habits = (await db.query('habits', where: 'archived=?', whereArgs: [archived ? 1 : 0], orderBy: 'position, id')).map(Habit.fromMap).toList();
    if (habits.isEmpty) return [];
    final logs = await db.query('habit_logs');
    final byHabit = <int, Set<int>>{};
    for (final l in logs) {
      (byHabit[l['habit_id'] as int] ??= <int>{}).add(l['day'] as int);
    }
    return habits.map((h) => HabitStats(h, byHabit[h.id] ?? <int>{})).toList();
  }

  Future<HabitStats?> get(int id) async {
    final rows = await db.query('habits', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final logs = await db.query('habit_logs', where: 'habit_id=?', whereArgs: [id]);
    return HabitStats(Habit.fromMap(rows.first), logs.map((l) => l['day'] as int).toSet());
  }

  Future<int> save(Habit h) async {
    final int id;
    if (h.id == null) {
      final pos = (await db.rawQuery('SELECT COALESCE(MAX(position),0)+1 p FROM habits')).first['p'] as int;
      id = await db.insert('habits', h.toMap()..['position'] = pos);
    } else {
      id = h.id!;
      await db.update('habits', h.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.habits);
    return id;
  }

  Future<void> setDone(int habitId, DateTime day, bool done) async {
    if (done) {
      await db.rawInsert('INSERT OR IGNORE INTO habit_logs(habit_id, day) VALUES(?, ?)', [habitId, D.dayKey(day)]);
    } else {
      await db.delete('habit_logs', where: 'habit_id=? AND day=?', whereArgs: [habitId, D.dayKey(day)]);
    }
    changed(Chg.habits);
  }

  Future<void> setArchived(int id, bool archived) async {
    await db.update('habits', {'archived': archived ? 1 : 0}, where: 'id=?', whereArgs: [id]);
    changed(Chg.habits);
  }

  Future<void> reorder(List<int> ids) async {
    final b = db.batch();
    for (var k = 0; k < ids.length; k++) {
      b.update('habits', {'position': k}, where: 'id=?', whereArgs: [ids[k]]);
    }
    await b.commit(noResult: true);
    changed(Chg.habits);
  }

  Future<void> delete(int id) async {
    await db.delete('habits', where: 'id=?', whereArgs: [id]);
    changed(Chg.habits);
  }

  /// Completions per day across all habits for heatmaps: dayKey → count.
  Future<Map<int, int>> dailyTotals(DateTime from) async {
    final rows = await db.rawQuery('SELECT day, COUNT(*) c FROM habit_logs WHERE day>=? GROUP BY day', [D.dayKey(from)]);
    return {for (final r in rows) r['day'] as int: r['c'] as int};
  }
}
