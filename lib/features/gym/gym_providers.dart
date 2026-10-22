import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dates.dart';
import '../../data/models/gym.dart';
import '../../data/repositories/base.dart';
import '../../data/repositories/gym_repo.dart';
import '../../state/providers.dart';

final activeWorkoutProvider = FutureProvider.autoDispose<Workout?>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).activeWorkout();
});

final workoutProvider = FutureProvider.autoDispose.family<Workout?, int>((ref, id) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).workout(id);
});

final routinesProvider = FutureProvider.autoDispose<List<Routine>>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).routines();
});

final todayRoutineProvider = FutureProvider.autoDispose<Routine?>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).routineForDay(DateTime.now());
});

final todayWorkoutProvider = FutureProvider.autoDispose<Workout?>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).workoutOn(DateTime.now());
});

final workoutHistoryProvider = FutureProvider.autoDispose<List<Workout>>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).history(limit: 100);
});

final exercisesProvider = FutureProvider.autoDispose.family<List<Exercise>, (Muscle?, String)>((ref, q) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).exercises(muscle: q.$1, search: q.$2);
});

final exerciseCountsProvider = FutureProvider.autoDispose<Map<Muscle, int>>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).exerciseCounts();
});

final exerciseProvider = FutureProvider.autoDispose.family<Exercise?, int>((ref, id) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).exercise(id);
});

final exerciseStatsProvider = FutureProvider.autoDispose.family<ExerciseStats, int>((ref, id) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).exerciseStats(id);
});

final gymOverviewProvider = FutureProvider.autoDispose<GymOverview>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).overview();
});

final gymWeeklyProvider = FutureProvider.autoDispose<List<(DateTime, int, double, double)>>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).weekly(12);
});

final muscleFrequencyProvider = FutureProvider.autoDispose<Map<Muscle, int>>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).muscleFrequency(30);
});

final personalRecordsProvider = FutureProvider.autoDispose<List<(Exercise, double, int)>>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).personalRecords();
});

final bodyKindsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).bodyKinds();
});

final bodyMetricsProvider = FutureProvider.autoDispose.family<List<BodyMetric>, String>((ref, kind) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).bodyMetrics(kind);
});

final latestBodyProvider = FutureProvider.autoDispose<Map<String, BodyMetric>>((ref) {
  ref.watchTopics([Chg.gym]);
  return ref.read(gymRepoProvider).latestBody();
});

/// Workout days in the current month for the training calendar strip.
final workoutDaysProvider = FutureProvider.autoDispose<Set<int>>((ref) async {
  ref.watchTopics([Chg.gym]);
  final from = D.addDays(D.today(), -120);
  final list = await ref.read(gymRepoProvider).workoutsBetween(from, D.endOfDay(DateTime.now()));
  return list.where((w) => !w.isActive).map((w) => D.dayKey(w.startedAt)).toSet();
});

String fmtWeight(double w, String unit) => '${w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toStringAsFixed(1)} $unit';
