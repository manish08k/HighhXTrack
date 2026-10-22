import '../../core/utils/dates.dart';
import '../models/planner.dart';
import 'base.dart';

class EventRepo extends Repo {
  EventRepo(super.db, super.changed);

  Future<CalEvent?> get(int id) async {
    final rows = await db.query('events', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : CalEvent.fromMap(rows.first);
  }

  Future<int> save(CalEvent e) async {
    final int id;
    if (e.id == null) {
      id = await db.insert('events', e.toMap());
    } else {
      id = e.id!;
      await db.update('events', e.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.calendar);
    return id;
  }

  Future<Map<String, Object?>?> delete(int id) async {
    final rows = await db.query('events', where: 'id=?', whereArgs: [id]);
    await db.delete('events', where: 'id=?', whereArgs: [id]);
    changed(Chg.calendar);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> restore(Map<String, Object?> row) async {
    await db.insert('events', row);
    changed(Chg.calendar);
  }

  /// Expanded occurrences (event, occurrenceStart) overlapping [from, to].
  Future<List<(CalEvent, DateTime)>> occurrences(DateTime from, DateTime to) async {
    final rows = await db.query('events', where: "start_at<=? AND (recurrence<>'' OR end_at>=?)", whereArgs: [D.ms(to), D.ms(from)]);
    final out = <(CalEvent, DateTime)>[];
    for (final e in rows.map(CalEvent.fromMap)) {
      if (e.recurrence.isNone) {
        out.add((e, e.start));
      } else {
        // Include occurrences that started before `from` but overlap it.
        final lookBack = from.subtract(e.length);
        for (final d in e.recurrence.occurrences(e.start, lookBack, to, max: 400)) {
          out.add((e, d));
        }
      }
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  Future<List<CalEvent>> search(String q) async {
    final l = Repo.like(q);
    final rows = await db.query(
      'events',
      where: "title LIKE ? ESCAPE '\\' OR notes LIKE ? ESCAPE '\\' OR location LIKE ? ESCAPE '\\'",
      whereArgs: [l, l, l],
      orderBy: 'start_at DESC',
      limit: 30,
    );
    return rows.map(CalEvent.fromMap).toList();
  }
}
