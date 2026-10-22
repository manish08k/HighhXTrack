import '../../core/utils/dates.dart';
import '../models/knowledge.dart';
import 'base.dart';

class StudyRepo extends Repo {
  StudyRepo(super.db, super.changed);

  // ------------------------------------------------------------ subjects
  Future<List<Subject>> subjects({bool archived = false}) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.*,
        (SELECT COUNT(*) FROM topics t WHERE t.subject_id=s.id) topic_count,
        (SELECT COUNT(*) FROM topics t WHERE t.subject_id=s.id AND t.done=1) topics_done,
        (SELECT COALESCE(SUM(duration_sec),0) FROM study_sessions x WHERE x.subject_id=s.id) total_sec
      FROM subjects s WHERE s.archived=? ORDER BY s.position, s.id''',
      [archived ? 1 : 0],
    );
    return rows.map(Subject.fromMap).toList();
  }

  Future<Subject?> subject(int id) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.*,
        (SELECT COUNT(*) FROM topics t WHERE t.subject_id=s.id) topic_count,
        (SELECT COUNT(*) FROM topics t WHERE t.subject_id=s.id AND t.done=1) topics_done,
        (SELECT COALESCE(SUM(duration_sec),0) FROM study_sessions x WHERE x.subject_id=s.id) total_sec
      FROM subjects s WHERE s.id=?''',
      [id],
    );
    return rows.isEmpty ? null : Subject.fromMap(rows.first);
  }

  Future<int> saveSubject(Subject s) async {
    final int id;
    if (s.id == null) {
      final pos = (await db.rawQuery('SELECT COALESCE(MAX(position),0)+1 p FROM subjects')).first['p'] as int;
      id = await db.insert('subjects', s.toMap()..['position'] = pos);
    } else {
      id = s.id!;
      await db.update('subjects', s.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.study);
    return id;
  }

  Future<void> deleteSubject(int id) async {
    await db.delete('subjects', where: 'id=?', whereArgs: [id]);
    changed(Chg.study);
  }

  // ------------------------------------------------------------ topics
  Future<List<Topic>> topics(int subjectId) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.*, (SELECT COALESCE(SUM(duration_sec),0) FROM study_sessions x WHERE x.topic_id=t.id) sec
      FROM topics t WHERE t.subject_id=? ORDER BY t.position, t.id''',
      [subjectId],
    );
    return rows.map(Topic.fromMap).toList();
  }

  Future<int> saveTopic({int? id, required int subjectId, required String name, String notes = ''}) async {
    final int out;
    if (id == null) {
      final pos = (await db.rawQuery('SELECT COALESCE(MAX(position),0)+1 p FROM topics WHERE subject_id=?', [subjectId])).first['p'] as int;
      out = await db.insert('topics', {'subject_id': subjectId, 'name': name, 'notes': notes, 'position': pos});
    } else {
      out = id;
      await db.update('topics', {'name': name, 'notes': notes}, where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.study);
    return out;
  }

  Future<void> setTopicDone(int id, bool done) async {
    await db.update('topics', {'done': done ? 1 : 0, 'done_at': done ? D.ms(DateTime.now()) : null}, where: 'id=?', whereArgs: [id]);
    changed(Chg.study);
  }

  Future<void> reorderTopics(List<int> ids) async {
    final b = db.batch();
    for (var k = 0; k < ids.length; k++) {
      b.update('topics', {'position': k}, where: 'id=?', whereArgs: [ids[k]]);
    }
    await b.commit(noResult: true);
    changed(Chg.study);
  }

  Future<void> deleteTopic(int id) async {
    await db.delete('topics', where: 'id=?', whereArgs: [id]);
    changed(Chg.study);
  }

  // ------------------------------------------------------------ sessions
  static const _sessionSelect = '''
    SELECT x.*, s.name subject_name, s.color subject_color, t.name topic_name FROM study_sessions x
    LEFT JOIN subjects s ON s.id=x.subject_id LEFT JOIN topics t ON t.id=x.topic_id''';

  Future<List<StudySession>> sessions({int? subjectId, int limit = 100}) async {
    final rows = await db.rawQuery('$_sessionSelect ${subjectId == null ? '' : 'WHERE x.subject_id=?'} ORDER BY x.started_at DESC LIMIT $limit', [?subjectId]);
    return rows.map(StudySession.fromMap).toList();
  }

  Future<List<StudySession>> sessionsBetween(DateTime from, DateTime to) async {
    final rows = await db.rawQuery('$_sessionSelect WHERE x.started_at>=? AND x.started_at<=? ORDER BY x.started_at', [D.ms(from), D.ms(to)]);
    return rows.map(StudySession.fromMap).toList();
  }

  Future<int> addSession(StudySession s) async {
    final id = await db.insert('study_sessions', s.toMap());
    changed(Chg.study);
    return id;
  }

  Future<Map<String, Object?>?> deleteSession(int id) async {
    final rows = await db.query('study_sessions', where: 'id=?', whereArgs: [id]);
    await db.delete('study_sessions', where: 'id=?', whereArgs: [id]);
    changed(Chg.study);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> restoreSession(Map<String, Object?> row) async {
    await db.insert('study_sessions', row);
    changed(Chg.study);
  }

  // ------------------------------------------------------------ stats
  Future<int> secondsBetween(DateTime from, DateTime to) async {
    final r = await db.rawQuery('SELECT COALESCE(SUM(duration_sec),0) s FROM study_sessions WHERE started_at>=? AND started_at<=?', [D.ms(from), D.ms(to)]);
    return r.first['s'] as int;
  }

  Future<int> totalSeconds() async => (await db.rawQuery('SELECT COALESCE(SUM(duration_sec),0) s FROM study_sessions')).first['s'] as int;

  /// Seconds per day for the last [days] days, oldest first.
  Future<List<int>> perDay(int days) async {
    final start = D.addDays(D.today(), -(days - 1));
    final rows = await db.query('study_sessions', columns: ['started_at', 'duration_sec'], where: 'started_at>=?', whereArgs: [D.ms(start)]);
    final out = List<int>.filled(days, 0);
    for (final r in rows) {
      final idx = D.diffDays(start, D.fromMs(r['started_at'] as int));
      if (idx >= 0 && idx < days) out[idx] += r['duration_sec'] as int;
    }
    return out;
  }

  /// Day keys with any study, for streaks and heatmaps: dayKey → seconds.
  Future<Map<int, int>> dayTotals({DateTime? from}) async {
    final rows = await db.query(
      'study_sessions',
      columns: ['started_at', 'duration_sec'],
      where: from == null ? null : 'started_at>=?',
      whereArgs: from == null ? null : [D.ms(from)],
    );
    final out = <int, int>{};
    for (final r in rows) {
      final k = D.dayKey(D.fromMs(r['started_at'] as int));
      out[k] = (out[k] ?? 0) + (r['duration_sec'] as int);
    }
    return out;
  }

  /// subject → seconds in the last [days] days (null days = all time).
  Future<List<(String, int, int)>> distribution({int? days}) async {
    final rows = await db.rawQuery('''
      SELECT s.name, s.color, SUM(x.duration_sec) sec FROM study_sessions x JOIN subjects s ON s.id=x.subject_id
      ${days == null ? '' : 'WHERE x.started_at>=${D.ms(D.addDays(D.today(), -days))}'}
      GROUP BY s.id ORDER BY sec DESC''');
    return rows.map((r) => (r['name'] as String, r['color'] as int, r['sec'] as int)).toList();
  }

  Future<(int, int)> topicCompletion() async {
    final r = await db.rawQuery('SELECT COALESCE(SUM(t.done),0) d, COUNT(*) c FROM topics t JOIN subjects s ON s.id=t.subject_id WHERE s.archived=0');
    return (r.first['d'] as int, r.first['c'] as int);
  }
}

/// Consecutive days (ending today or yesterday) with any study.
int studyStreak(Map<int, int> dayTotals) {
  var d = D.today();
  if (!dayTotals.containsKey(D.dayKey(d))) d = D.addDays(d, -1);
  var n = 0;
  while (dayTotals.containsKey(D.dayKey(d))) {
    n++;
    d = D.addDays(d, -1);
  }
  return n;
}

int bestStudyStreak(Map<int, int> dayTotals) {
  if (dayTotals.isEmpty) return 0;
  final keys = dayTotals.keys.toList()..sort();
  var best = 1, cur = 1;
  for (var k = 1; k < keys.length; k++) {
    if (D.diffDays(D.fromDayKey(keys[k - 1]), D.fromDayKey(keys[k])) == 1) {
      cur++;
      if (cur > best) best = cur;
    } else {
      cur = 1;
    }
  }
  return best;
}
