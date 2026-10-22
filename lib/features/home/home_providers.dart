import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dates.dart';
import '../../data/models/gym.dart';
import '../../data/models/money.dart';
import '../../data/models/planner.dart';
import '../../data/repositories/base.dart';
import '../../state/providers.dart';
import '../calendar/calendar_data.dart';

class HomeData {
  const HomeData({
    required this.todoDone,
    required this.todoTotal,
    required this.reminders,
    required this.todayWorkout,
    required this.activeWorkout,
    required this.routine,
    required this.habitsDone,
    required this.habitsDue,
    required this.money,
    required this.studySec,
    required this.upcoming,
    required this.expiringDocs,
  });

  final int todoDone;
  final int todoTotal;
  final List<Reminder> reminders;
  final Workout? todayWorkout;
  final Workout? activeWorkout;
  final Routine? routine;
  final int habitsDone;
  final int habitsDue;
  final MonthSummary money;
  final int studySec;
  final List<CalItem> upcoming;
  final List<Doc> expiringDocs;
}

/// Everything the Home dashboard needs, in one load.
final homeProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  ref.watchTopics(Chg.all);
  final budget = ref.watch(settingsProvider.select((s) => s.monthlyBudget));
  final now = DateTime.now();
  // Watched before any await so the dependency is registered synchronously.
  final itemsFuture = ref.watch(calendarItemsProvider((D.today(), D.endOfDay(D.addDays(D.today(), 7)))).future);
  final (td, tt) = await ref.read(todoRepoProvider).todayProgress();
  final habits = await ref.read(habitRepoProvider).all();
  final due = habits.where((h) => h.habit.scheduledOn(now)).toList();
  final gym = ref.read(gymRepoProvider);
  final items = await itemsFuture;
  final docs = (await ref.read(documentRepoProvider).all()).where((d) => d.status == DocStatus.expiring || d.status == DocStatus.expired).toList();
  return HomeData(
    todoDone: td,
    todoTotal: tt,
    reminders: await ref.read(reminderRepoProvider).upcoming(limit: 3),
    todayWorkout: await gym.workoutOn(now),
    activeWorkout: await gym.activeWorkout(),
    routine: await gym.routineForDay(now),
    habitsDone: due.where((h) => h.doneToday).length,
    habitsDue: due.length,
    money: await ref.read(moneyRepoProvider).summary(now, budget: budget),
    studySec: await ref.read(studyRepoProvider).secondsBetween(D.today(), D.endOfDay(now)),
    upcoming: items.where((i) => i.start.isAfter(now) && !i.done).take(5).toList(),
    expiringDocs: docs.take(3).toList(),
  );
});
