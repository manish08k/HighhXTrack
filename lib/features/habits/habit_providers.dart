import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dates.dart';
import '../../data/models/planner.dart';
import '../../data/repositories/base.dart';
import '../../state/providers.dart';

final habitsProvider = FutureProvider.autoDispose<List<HabitStats>>((ref) {
  ref.watchTopics([Chg.habits]);
  return ref.read(habitRepoProvider).all();
});

final archivedHabitsProvider = FutureProvider.autoDispose<List<HabitStats>>((ref) {
  ref.watchTopics([Chg.habits]);
  return ref.read(habitRepoProvider).all(archived: true);
});

final habitProvider = FutureProvider.autoDispose.family<HabitStats?, int>((ref, id) {
  ref.watchTopics([Chg.habits]);
  return ref.read(habitRepoProvider).get(id);
});

final habitDailyTotalsProvider = FutureProvider.autoDispose<Map<int, int>>((ref) {
  ref.watchTopics([Chg.habits]);
  return ref.read(habitRepoProvider).dailyTotals(D.addDays(D.today(), -7 * 26));
});

/// (done today, scheduled today) across active habits.
(int, int) todayHabitProgress(List<HabitStats> list) {
  final today = DateTime.now();
  final due = list
      .where((h) => h.habit.scheduledOn(today) && !(h.habit.schedule == HabitSchedule.weekly && h.doneThisWeek >= h.habit.weeklyTarget && !h.doneToday))
      .toList();
  return (due.where((h) => h.doneToday).length, due.length);
}

Future<void> toggleHabit(BuildContext context, WidgetRef ref, HabitStats h, {DateTime? day}) async {
  HapticFeedback.lightImpact();
  final d = day ?? DateTime.now();
  await ref.read(habitRepoProvider).setDone(h.habit.id!, d, !h.doneOn(d));
}
