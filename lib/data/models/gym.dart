import 'dart:ui';

import '../../core/utils/dates.dart';
import 'common.dart';

enum Muscle {
  chest('Chest', Color(0xFFE5484D)),
  back('Back', Color(0xFF2D8CDB)),
  shoulders('Shoulders', Color(0xFFF2711C)),
  biceps('Biceps', Color(0xFF8E4EC6)),
  triceps('Triceps', Color(0xFFD6409F)),
  legs('Legs', Color(0xFF1FA971)),
  abs('Abs', Color(0xFFE8A317)),
  forearms('Forearms', Color(0xFF14A3B8)),
  calves('Calves', Color(0xFF607D8B));

  const Muscle(this.label, this.color);
  final String label;
  final Color color;

  static Muscle byName(String s) => Muscle.values.firstWhere((m) => m.name == s, orElse: () => Muscle.chest);
}

class Exercise {
  const Exercise({this.id, required this.name, required this.muscle, this.notes = '', this.restSeconds = 90, this.isCustom = false, this.archived = false});

  final int? id;
  final String name;
  final Muscle muscle;
  final String notes;
  final int restSeconds;
  final bool isCustom;
  final bool archived;

  factory Exercise.fromMap(Map<String, Object?> m) => Exercise(
    id: m['id'] as int,
    name: m['name'] as String,
    muscle: Muscle.byName(m['muscle'] as String),
    notes: m['notes'] as String? ?? '',
    restSeconds: m['rest_seconds'] as int? ?? 90,
    isCustom: b(m['is_custom']),
    archived: b(m['archived']),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'muscle': muscle.name,
    'notes': notes,
    'rest_seconds': restSeconds,
    'is_custom': i(isCustom),
    'archived': i(archived),
  };
}

class RoutineExercise {
  const RoutineExercise({this.id, required this.exerciseId, this.sets = 3, this.reps = 10, this.position = 0, this.exerciseName = '', this.muscle});
  final int? id;
  final int exerciseId;
  final int sets;
  final int reps;
  final int position;
  final String exerciseName;
  final Muscle? muscle;

  RoutineExercise copyWith({int? sets, int? reps, int? position}) => RoutineExercise(
    id: id,
    exerciseId: exerciseId,
    sets: sets ?? this.sets,
    reps: reps ?? this.reps,
    position: position ?? this.position,
    exerciseName: exerciseName,
    muscle: muscle,
  );
}

/// A reusable workout template ("Push Day") optionally scheduled on weekdays.
class Routine {
  const Routine({this.id, required this.name, this.weekdays = const {}, this.remindMinutes, this.color = 0, this.items = const []});
  final int? id;
  final String name;
  final Set<int> weekdays;
  final int? remindMinutes;
  final int color;
  final List<RoutineExercise> items;

  factory Routine.fromMap(Map<String, Object?> m, [List<RoutineExercise> items = const []]) => Routine(
    id: m['id'] as int,
    name: m['name'] as String,
    weekdays: _decodeDays(m['weekdays'] as String?),
    remindMinutes: m['remind_minutes'] as int?,
    color: m['color'] as int? ?? 0,
    items: items,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'weekdays': (weekdays.toList()..sort()).join(','),
    'remind_minutes': remindMinutes,
    'color': color,
  };
}

Set<int> _decodeDays(String? s) => (s == null || s.isEmpty) ? <int>{} : s.split(',').map(int.parse).toSet();

Set<int> decodeWeekdays(String? s) => _decodeDays(s);

enum SetStatus { pending, done, skipped }

class WorkoutSet {
  const WorkoutSet({
    this.id,
    required this.workoutExerciseId,
    this.position = 0,
    this.weight = 0,
    this.reps = 0,
    this.status = SetStatus.pending,
    this.completedAt,
  });
  final int? id;
  final int workoutExerciseId;
  final int position;
  final double weight;
  final int reps;
  final SetStatus status;
  final DateTime? completedAt;

  double get volume => status == SetStatus.done ? weight * reps : 0;

  factory WorkoutSet.fromMap(Map<String, Object?> m) => WorkoutSet(
    id: m['id'] as int,
    workoutExerciseId: m['workout_exercise_id'] as int,
    position: m['position'] as int? ?? 0,
    weight: (m['weight'] as num?)?.toDouble() ?? 0,
    reps: m['reps'] as int? ?? 0,
    status: SetStatus.values[(m['status'] as int? ?? 0).clamp(0, 2)],
    completedAt: D.fromMsN(m['completed_at'] as int?),
  );
}

class WorkoutExercise {
  const WorkoutExercise({required this.id, required this.workoutId, required this.exercise, this.position = 0, this.notes = '', this.sets = const []});
  final int id;
  final int workoutId;
  final Exercise exercise;
  final int position;
  final String notes;
  final List<WorkoutSet> sets;

  int get doneSets => sets.where((s) => s.status == SetStatus.done).length;
  double get volume => sets.fold(0, (a, s) => a + s.volume);
}

class Workout {
  const Workout({this.id, required this.name, this.routineId, required this.startedAt, this.endedAt, this.notes = '', this.exercises = const []});
  final int? id;
  final String name;
  final int? routineId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String notes;
  final List<WorkoutExercise> exercises;

  bool get isActive => endedAt == null;
  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);
  int get totalSets => exercises.fold(0, (a, e) => a + e.doneSets);
  double get volume => exercises.fold(0, (a, e) => a + e.volume);

  factory Workout.fromMap(Map<String, Object?> m, [List<WorkoutExercise> ex = const []]) => Workout(
    id: m['id'] as int,
    name: m['name'] as String,
    routineId: m['routine_id'] as int?,
    startedAt: D.fromMs(m['started_at'] as int),
    endedAt: D.fromMsN(m['ended_at'] as int?),
    notes: m['notes'] as String? ?? '',
    exercises: ex,
  );
}

/// Body weight & measurements. Built-in kinds plus any custom name.
abstract final class BodyKind {
  static const weight = 'Weight';
  static const builtIn = ['Weight', 'Chest', 'Waist', 'Arms', 'Thighs', 'Shoulders'];
  static String unit(String kind) => kind == weight ? 'kg' : 'cm';
}

class BodyMetric {
  const BodyMetric({this.id, required this.kind, required this.value, required this.measuredAt});
  final int? id;
  final String kind;
  final double value;
  final DateTime measuredAt;

  factory BodyMetric.fromMap(Map<String, Object?> m) =>
      BodyMetric(id: m['id'] as int, kind: m['kind'] as String, value: (m['value'] as num).toDouble(), measuredAt: D.fromMs(m['measured_at'] as int));
}

/// Last/best performance of an exercise.
class ExerciseStats {
  const ExerciseStats({
    this.bestWeight = 0,
    this.bestWeightReps = 0,
    this.bestVolumeSet = 0,
    this.best1rm = 0,
    this.lastSets = const [],
    this.lastDate,
    this.history = const [],
  });
  final double bestWeight;
  final int bestWeightReps;
  final double bestVolumeSet;
  final double best1rm;
  final List<WorkoutSet> lastSets;
  final DateTime? lastDate;

  /// (date, heaviest weight that session, session volume)
  final List<(DateTime, double, double)> history;
}

/// Epley estimated one-rep max.
double estimate1rm(double weight, int reps) => reps <= 0 ? 0 : (reps == 1 ? weight : weight * (1 + reps / 30));
