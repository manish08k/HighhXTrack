import 'package:sqflite/sqflite.dart';

import '../../core/utils/dates.dart';
import '../models/gym.dart';
import 'base.dart';

class GymOverview {
  const GymOverview({this.total = 0, this.thisWeek = 0, this.thisMonth = 0, this.avgDuration = Duration.zero});
  final int total;
  final int thisWeek;
  final int thisMonth;
  final Duration avgDuration;
}

class GymRepo extends Repo {
  GymRepo(super.db, super.changed);

  // ------------------------------------------------------------ exercises
  Future<List<Exercise>> exercises({Muscle? muscle, String search = ''}) async {
    final where = <String>['archived=0'];
    final args = <Object?>[];
    if (muscle != null) {
      where.add('muscle=?');
      args.add(muscle.name);
    }
    if (search.trim().isNotEmpty) {
      where.add("name LIKE ? ESCAPE '\\'");
      args.add(Repo.like(search.trim()));
    }
    final rows = await db.query('exercises', where: where.join(' AND '), whereArgs: args, orderBy: 'name COLLATE NOCASE');
    return rows.map(Exercise.fromMap).toList();
  }

  Future<Map<Muscle, int>> exerciseCounts() async {
    final rows = await db.rawQuery('SELECT muscle, COUNT(*) c FROM exercises WHERE archived=0 GROUP BY muscle');
    return {for (final r in rows) Muscle.byName(r['muscle'] as String): r['c'] as int};
  }

  Future<Exercise?> exercise(int id) async {
    final rows = await db.query('exercises', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : Exercise.fromMap(rows.first);
  }

  Future<int> saveExercise(Exercise e) async {
    final int id;
    if (e.id == null) {
      id = await db.insert('exercises', e.toMap());
    } else {
      id = e.id!;
      await db.update('exercises', e.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.gym);
    return id;
  }

  /// Exercises with history are archived (history kept); others deleted.
  Future<void> deleteExercise(int id) async {
    final used = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM workout_exercises WHERE exercise_id=?', [id])) ?? 0;
    if (used > 0) {
      await db.update('exercises', {'archived': 1}, where: 'id=?', whereArgs: [id]);
    } else {
      await db.delete('exercises', where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.gym);
  }

  // ------------------------------------------------------------ routines
  Future<List<Routine>> routines() async {
    final rows = await db.query('routines', orderBy: 'position, id');
    final items = await db.rawQuery('''
      SELECT re.*, e.name ex_name, e.muscle ex_muscle FROM routine_exercises re
      JOIN exercises e ON e.id = re.exercise_id ORDER BY re.position, re.id''');
    final byRoutine = <int, List<RoutineExercise>>{};
    for (final r in items) {
      (byRoutine[r['routine_id'] as int] ??= []).add(
        RoutineExercise(
          id: r['id'] as int,
          exerciseId: r['exercise_id'] as int,
          sets: r['sets'] as int,
          reps: r['reps'] as int,
          position: r['position'] as int,
          exerciseName: r['ex_name'] as String,
          muscle: Muscle.byName(r['ex_muscle'] as String),
        ),
      );
    }
    return rows.map((r) => Routine.fromMap(r, byRoutine[r['id']] ?? const [])).toList();
  }

  Future<Routine?> routineForDay(DateTime day) async {
    for (final r in await routines()) {
      if (r.weekdays.contains(day.weekday)) return r;
    }
    return null;
  }

  Future<int> saveRoutine(Routine r, List<RoutineExercise> items) async {
    late int id;
    await db.transaction((tx) async {
      if (r.id == null) {
        id = await tx.insert('routines', r.toMap());
      } else {
        id = r.id!;
        await tx.update('routines', r.toMap(), where: 'id=?', whereArgs: [id]);
        await tx.delete('routine_exercises', where: 'routine_id=?', whereArgs: [id]);
      }
      var pos = 0;
      for (final it in items) {
        await tx.insert('routine_exercises', {'routine_id': id, 'exercise_id': it.exerciseId, 'sets': it.sets, 'reps': it.reps, 'position': pos++});
      }
    });
    changed(Chg.gym);
    return id;
  }

  Future<void> deleteRoutine(int id) async {
    await db.delete('routines', where: 'id=?', whereArgs: [id]);
    changed(Chg.gym);
  }

  // ------------------------------------------------------------ workouts
  Future<Workout?> activeWorkout() async {
    final rows = await db.query('workouts', where: 'ended_at IS NULL', orderBy: 'started_at DESC', limit: 1);
    if (rows.isEmpty) return null;
    return _hydrate(rows.first);
  }

  Future<Workout?> workout(int id) async {
    final rows = await db.query('workouts', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : _hydrate(rows.first);
  }

  Future<Workout> _hydrate(Map<String, Object?> w) async {
    final id = w['id'] as int;
    final wex = await db.rawQuery(
      '''
      SELECT we.id we_id, we.position we_pos, we.notes we_notes, e.* FROM workout_exercises we
      JOIN exercises e ON e.id = we.exercise_id WHERE we.workout_id=? ORDER BY we.position, we.id''',
      [id],
    );
    final sets = await db.rawQuery(
      '''
      SELECT s.* FROM workout_sets s JOIN workout_exercises we ON we.id = s.workout_exercise_id
      WHERE we.workout_id=? ORDER BY s.position, s.id''',
      [id],
    );
    final byWe = <int, List<WorkoutSet>>{};
    for (final s in sets) {
      final ws = WorkoutSet.fromMap(s);
      (byWe[ws.workoutExerciseId] ??= []).add(ws);
    }
    final ex = wex
        .map(
          (r) => WorkoutExercise(
            id: r['we_id'] as int,
            workoutId: id,
            exercise: Exercise.fromMap(r),
            position: r['we_pos'] as int,
            notes: r['we_notes'] as String? ?? '',
            sets: byWe[r['we_id']] ?? const [],
          ),
        )
        .toList();
    return Workout.fromMap(w, ex);
  }

  /// Finished workouts, newest first, with summary info.
  Future<List<Workout>> history({int limit = 50, int offset = 0}) async {
    final rows = await db.query('workouts', where: 'ended_at IS NOT NULL', orderBy: 'started_at DESC', limit: limit, offset: offset);
    return Future.wait(rows.map(_hydrate));
  }

  Future<List<Workout>> workoutsBetween(DateTime from, DateTime to) async {
    final rows = await db.query('workouts', where: 'started_at>=? AND started_at<=?', whereArgs: [D.ms(from), D.ms(to)], orderBy: 'started_at');
    return rows.map((r) => Workout.fromMap(r)).toList();
  }

  Future<Workout?> workoutOn(DateTime day) async {
    final rows = await db.query(
      'workouts',
      where: 'started_at>=? AND started_at<=?',
      whereArgs: [D.ms(D.dateOnly(day)), D.ms(D.endOfDay(day))],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _hydrate(rows.first);
  }

  Future<int> startWorkout({required String name, Routine? routine}) async {
    final existing = await activeWorkout();
    if (existing != null) return existing.id!;
    late int id;
    await db.transaction((tx) async {
      id = await tx.insert('workouts', {'name': name, 'routine_id': routine?.id, 'started_at': D.ms(DateTime.now())});
      if (routine != null) {
        var pos = 0;
        for (final it in routine.items) {
          await _addExercise(tx, id, it.exerciseId, pos++, targetSets: it.sets, targetReps: it.reps);
        }
      }
    });
    changed(Chg.gym);
    return id;
  }

  Future<void> addExercise(int workoutId, int exerciseId) async {
    await db.transaction((tx) async {
      final pos = Sqflite.firstIntValue(await tx.rawQuery('SELECT COALESCE(MAX(position),-1)+1 FROM workout_exercises WHERE workout_id=?', [workoutId])) ?? 0;
      await _addExercise(tx, workoutId, exerciseId, pos);
    });
    changed(Chg.gym);
  }

  /// Adds an exercise prefilled with the previous session's sets.
  Future<void> _addExercise(DatabaseExecutor tx, int workoutId, int exerciseId, int pos, {int? targetSets, int? targetReps}) async {
    final weId = await tx.insert('workout_exercises', {'workout_id': workoutId, 'exercise_id': exerciseId, 'position': pos});
    final last = await _lastSets(tx, exerciseId, excludeWorkout: workoutId);
    final n = targetSets ?? (last.isEmpty ? 3 : last.length);
    for (var k = 0; k < n; k++) {
      final prev = last.isEmpty ? null : last[k < last.length ? k : last.length - 1];
      await tx.insert('workout_sets', {
        'workout_exercise_id': weId,
        'position': k,
        'weight': prev?.weight ?? 0,
        'reps': targetReps ?? prev?.reps ?? 10,
        'status': 0,
      });
    }
  }

  Future<List<WorkoutSet>> _lastSets(DatabaseExecutor ex, int exerciseId, {int? excludeWorkout}) async {
    final we = await ex.rawQuery(
      '''
      SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id
      WHERE we.exercise_id=? AND w.ended_at IS NOT NULL ${excludeWorkout != null ? 'AND w.id<>$excludeWorkout' : ''}
      AND EXISTS (SELECT 1 FROM workout_sets s WHERE s.workout_exercise_id=we.id AND s.status=1)
      ORDER BY w.started_at DESC LIMIT 1''',
      [exerciseId],
    );
    if (we.isEmpty) return [];
    final rows = await ex.query('workout_sets', where: 'workout_exercise_id=? AND status=1', whereArgs: [we.first['id']], orderBy: 'position');
    return rows.map(WorkoutSet.fromMap).toList();
  }

  Future<void> addSet(int workoutExerciseId) async {
    final last = await db.query('workout_sets', where: 'workout_exercise_id=?', whereArgs: [workoutExerciseId], orderBy: 'position DESC', limit: 1);
    final pos = last.isEmpty ? 0 : (last.first['position'] as int) + 1;
    await db.insert('workout_sets', {
      'workout_exercise_id': workoutExerciseId,
      'position': pos,
      'weight': last.isEmpty ? 0 : last.first['weight'],
      'reps': last.isEmpty ? 10 : last.first['reps'],
      'status': 0,
    });
    changed(Chg.gym);
  }

  Future<void> updateSet(int setId, {double? weight, int? reps}) async {
    await db.update('workout_sets', {'weight': ?weight, 'reps': ?reps}, where: 'id=?', whereArgs: [setId]);
    changed(Chg.gym);
  }

  Future<void> setStatus(int setId, SetStatus status) async {
    await db.update(
      'workout_sets',
      {'status': status.index, 'completed_at': status == SetStatus.pending ? null : D.ms(DateTime.now())},
      where: 'id=?',
      whereArgs: [setId],
    );
    changed(Chg.gym);
  }

  Future<void> deleteSet(int setId) async {
    await db.delete('workout_sets', where: 'id=?', whereArgs: [setId]);
    changed(Chg.gym);
  }

  Future<void> removeWorkoutExercise(int weId) async {
    await db.delete('workout_exercises', where: 'id=?', whereArgs: [weId]);
    changed(Chg.gym);
  }

  Future<void> updateWorkoutExerciseNotes(int weId, String notes) async {
    await db.update('workout_exercises', {'notes': notes}, where: 'id=?', whereArgs: [weId]);
    changed(Chg.gym);
  }

  Future<void> updateWorkoutNotes(int id, String notes) async {
    await db.update('workouts', {'notes': notes}, where: 'id=?', whereArgs: [id]);
    changed(Chg.gym);
  }

  Future<void> renameWorkout(int id, String name) async {
    await db.update('workouts', {'name': name}, where: 'id=?', whereArgs: [id]);
    changed(Chg.gym);
  }

  /// Ends the workout. Pending sets are dropped so history reflects work done.
  Future<void> finishWorkout(int id, {String notes = ''}) async {
    await db.transaction((tx) async {
      await tx.rawDelete('DELETE FROM workout_sets WHERE status=0 AND workout_exercise_id IN (SELECT id FROM workout_exercises WHERE workout_id=?)', [id]);
      await tx.rawDelete(
        'DELETE FROM workout_exercises WHERE workout_id=? AND NOT EXISTS (SELECT 1 FROM workout_sets s WHERE s.workout_exercise_id=workout_exercises.id)',
        [id],
      );
      await tx.update('workouts', {'ended_at': D.ms(DateTime.now()), 'notes': notes}, where: 'id=?', whereArgs: [id]);
    });
    changed(Chg.gym);
  }

  Future<void> deleteWorkout(int id) async {
    await db.delete('workouts', where: 'id=?', whereArgs: [id]);
    changed(Chg.gym);
  }

  // ------------------------------------------------------------ stats
  Future<ExerciseStats> exerciseStats(int exerciseId) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.weight, s.reps, w.started_at, w.id wid FROM workout_sets s
      JOIN workout_exercises we ON we.id = s.workout_exercise_id
      JOIN workouts w ON w.id = we.workout_id
      WHERE we.exercise_id=? AND s.status=1 AND w.ended_at IS NOT NULL
      ORDER BY w.started_at ASC''',
      [exerciseId],
    );
    double bestW = 0, bestVol = 0, best1rm = 0;
    var bestWReps = 0;
    final sessions = <int, (DateTime, double, double)>{};
    for (final r in rows) {
      final w = (r['weight'] as num).toDouble();
      final reps = r['reps'] as int;
      if (w > bestW || (w == bestW && reps > bestWReps)) {
        bestW = w;
        bestWReps = reps;
      }
      if (w * reps > bestVol) bestVol = w * reps;
      final e1 = estimate1rm(w, reps);
      if (e1 > best1rm) best1rm = e1;
      final wid = r['wid'] as int;
      final prev = sessions[wid];
      final date = D.fromMs(r['started_at'] as int);
      sessions[wid] = (date, prev == null || w > prev.$2 ? w : prev.$2, (prev?.$3 ?? 0) + w * reps);
    }
    final last = await _lastSets(db, exerciseId);
    final lastDate = sessions.isEmpty ? null : sessions.values.last.$1;
    return ExerciseStats(
      bestWeight: bestW,
      bestWeightReps: bestWReps,
      bestVolumeSet: bestVol,
      best1rm: best1rm,
      lastSets: last,
      lastDate: lastDate,
      history: sessions.values.toList(),
    );
  }

  /// PR (heaviest weight) per exercise that has history.
  Future<List<(Exercise, double, int)>> personalRecords() async {
    final rows = await db.rawQuery('''
      SELECT e.*, MAX(s.weight) best,
        (SELECT s2.reps FROM workout_sets s2 JOIN workout_exercises we2 ON we2.id=s2.workout_exercise_id
          WHERE we2.exercise_id=e.id AND s2.status=1 ORDER BY s2.weight DESC, s2.reps DESC LIMIT 1) reps
      FROM workout_sets s JOIN workout_exercises we ON we.id = s.workout_exercise_id
      JOIN exercises e ON e.id = we.exercise_id
      WHERE s.status=1 AND s.weight > 0 GROUP BY e.id ORDER BY e.muscle, e.name''');
    return rows.map((r) => (Exercise.fromMap(r), (r['best'] as num).toDouble(), r['reps'] as int? ?? 0)).toList();
  }

  Future<GymOverview> overview() async {
    final now = DateTime.now();
    Future<int> count(DateTime from) async =>
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM workouts WHERE ended_at IS NOT NULL AND started_at>=?', [D.ms(from)])) ?? 0;
    final total = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM workouts WHERE ended_at IS NOT NULL')) ?? 0;
    final avg = await db.rawQuery('SELECT AVG(ended_at - started_at) a FROM workouts WHERE ended_at IS NOT NULL');
    return GymOverview(
      total: total,
      thisWeek: await count(D.startOfWeek(now)),
      thisMonth: await count(D.startOfMonth(now)),
      avgDuration: Duration(milliseconds: ((avg.first['a'] as num?) ?? 0).round()),
    );
  }

  /// Per-week (workout count, volume, avg minutes) for the last [weeks] weeks, oldest first.
  Future<List<(DateTime, int, double, double)>> weekly(int weeks) async {
    final start = D.addDays(D.startOfWeek(DateTime.now()), -7 * (weeks - 1));
    final rows = await db.rawQuery(
      '''
      SELECT w.id, w.started_at, w.ended_at,
        (SELECT COALESCE(SUM(s.weight*s.reps),0) FROM workout_sets s JOIN workout_exercises we ON we.id=s.workout_exercise_id
          WHERE we.workout_id=w.id AND s.status=1) vol
      FROM workouts w WHERE w.ended_at IS NOT NULL AND w.started_at>=?''',
      [D.ms(start)],
    );
    final count = List<int>.filled(weeks, 0);
    final vol = List<double>.filled(weeks, 0);
    final mins = List<double>.filled(weeks, 0);
    for (final r in rows) {
      final idx = D.diffDays(start, D.fromMs(r['started_at'] as int)) ~/ 7;
      if (idx < 0 || idx >= weeks) continue;
      count[idx]++;
      vol[idx] += (r['vol'] as num).toDouble();
      mins[idx] += ((r['ended_at'] as int) - (r['started_at'] as int)) / 60000;
    }
    return [for (var k = 0; k < weeks; k++) (D.addDays(start, 7 * k), count[k], vol[k], count[k] == 0 ? 0 : mins[k] / count[k])];
  }

  /// Sessions per muscle group in the last [days] days.
  Future<Map<Muscle, int>> muscleFrequency(int days) async {
    final rows = await db.rawQuery(
      '''
      SELECT e.muscle, COUNT(DISTINCT w.id) c FROM workout_exercises we
      JOIN workouts w ON w.id = we.workout_id JOIN exercises e ON e.id = we.exercise_id
      WHERE w.ended_at IS NOT NULL AND w.started_at>=? GROUP BY e.muscle''',
      [D.ms(D.addDays(D.today(), -days))],
    );
    return {for (final r in rows) Muscle.byName(r['muscle'] as String): r['c'] as int};
  }

  // ------------------------------------------------------------ body
  Future<List<String>> bodyKinds() async {
    final rows = await db.rawQuery('SELECT DISTINCT kind FROM body_metrics');
    final custom = rows.map((r) => r['kind'] as String).where((k) => !BodyKind.builtIn.contains(k)).toList()..sort();
    return [...BodyKind.builtIn, ...custom];
  }

  Future<List<BodyMetric>> bodyMetrics(String kind) async {
    final rows = await db.query('body_metrics', where: 'kind=?', whereArgs: [kind], orderBy: 'measured_at ASC');
    return rows.map(BodyMetric.fromMap).toList();
  }

  Future<Map<String, BodyMetric>> latestBody() async {
    final rows = await db.rawQuery(
      'SELECT b.* FROM body_metrics b JOIN (SELECT kind, MAX(measured_at) m FROM body_metrics GROUP BY kind) x ON x.kind=b.kind AND x.m=b.measured_at',
    );
    return {for (final r in rows) r['kind'] as String: BodyMetric.fromMap(r)};
  }

  Future<void> addBodyMetric(String kind, double value, DateTime at) async {
    await db.insert('body_metrics', {'kind': kind, 'value': value, 'measured_at': D.ms(at)});
    changed(Chg.gym);
  }

  Future<Map<String, Object?>?> deleteBodyMetric(int id) async {
    final rows = await db.query('body_metrics', where: 'id=?', whereArgs: [id]);
    await db.delete('body_metrics', where: 'id=?', whereArgs: [id]);
    changed(Chg.gym);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> restoreRow(String table, Map<String, Object?> row) async {
    await db.insert(table, row);
    changed(Chg.gym);
  }
}
