import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newone/core/modules.dart';
import 'package:newone/core/utils/dates.dart';
import 'package:newone/core/utils/recurrence.dart';
import 'package:newone/data/db/app_database.dart';
import 'package:newone/data/models/gym.dart';
import 'package:newone/data/models/money.dart';
import 'package:newone/data/models/planner.dart';
import 'package:newone/data/models/todo.dart';
import 'package:newone/data/repositories/settings_repo.dart';
import 'package:newone/services/notification_planner.dart';
import 'package:newone/services/notification_service.dart';
import 'package:newone/state/providers.dart';

import 'helpers.dart';

final _planner = Provider((ref) => NotificationPlanner(ref));

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    setUpTempPaths();
    db = await openTestDb();
    c = await makeContainer(db, settings: const AppSettings(studyReminderMin: 23 * 60 + 59));
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<void> seed() async {
    final now = DateTime.now();
    final tomorrow = D.addDays(D.today(), 1);
    await c
        .read(todoRepoProvider)
        .save(
          Todo(title: 'Submit report', dueAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15), hasTime: true, createdAt: now, updatedAt: now),
          [],
        );
    await c.read(todoRepoProvider).save(Todo(title: 'No reminder', dueAt: tomorrow, remind: false, createdAt: now, updatedAt: now), []);
    await c
        .read(reminderRepoProvider)
        .save(Reminder(title: 'Vitamins', dueAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8), recurrence: Recurrence.daily, createdAt: now));
    await c.read(habitRepoProvider).save(Habit(name: 'Meditate', icon: 17, color: 0xFF000000, remindMinutes: 23 * 60 + 58, createdAt: now));
    await c
        .read(documentRepoProvider)
        .save(Doc(name: 'Licence', category: 'Driving License', expiryAt: D.addDays(D.today(), 40), remindDays: 30, createdAt: now));
    final anchor = D.addDays(D.today(), 2);
    await c.read(moneyRepoProvider).saveRecurring(RecurringTxn(title: 'Rent', amount: 2000000, recurrence: Recurrence.monthly, anchor: anchor, next: anchor));
    await c
        .read(eventRepoProvider)
        .save(
          CalEvent(
            title: 'Team sync',
            start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10),
            end: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 11),
            color: AppModule.calendar.color.toARGB32(),
            recurrence: const Recurrence(RepeatFreq.weekly),
            remindBefore: 15,
            createdAt: now,
          ),
        );
    final bench = (await c.read(gymRepoProvider).exercises(search: 'Bench Press')).first;
    await c.read(gymRepoProvider).saveRoutine(const Routine(name: 'Push', weekdays: {1, 3, 5}, remindMinutes: 23 * 60 + 57), [
      RoutineExercise(exerciseId: bench.id!),
    ]);
  }

  test('plans every category, expands recurrences, all in the future', () async {
    await seed();
    final now = DateTime.now();
    final plan = await c.read(_planner).plan(now: now);
    int count(NotifChannel ch) => plan.where((p) => p.channel == ch).length;

    expect(count(NotifChannel.todo), 1, reason: 'remind=false todo is skipped');
    expect(count(NotifChannel.reminders), 14, reason: 'daily reminder over 14 days');
    expect(count(NotifChannel.habits), inInclusiveRange(14, 15));
    expect(count(NotifChannel.documents), 1, reason: 'renewal reminder in 10 days; expiry day outside horizon');
    expect(count(NotifChannel.bills), 1);
    expect(count(NotifChannel.calendar), 2, reason: 'weekly event, 2 occurrences in 14 days');
    expect(count(NotifChannel.gym), inInclusiveRange(6, 7));
    expect(count(NotifChannel.study), inInclusiveRange(14, 15));

    expect(plan.every((p) => p.at.isAfter(now)), isTrue);
    expect(plan.map((p) => p.id).toSet().length, plan.length, reason: 'ids are unique');
    expect(plan.every((p) => p.id >= NotificationService.plannedBase), isTrue);
    for (var k = 1; k < plan.length; k++) {
      expect(plan[k].at.isBefore(plan[k - 1].at), isFalse, reason: 'sorted by time');
    }
    final todo = plan.firstWhere((p) => p.channel == NotifChannel.todo);
    expect(todo.payload, startsWith('todo:'));
    final ev = plan.firstWhere((p) => p.channel == NotifChannel.calendar);
    expect(ev.at.hour, 9);
    expect(ev.at.minute, 45);
  });

  test('disabled categories and completed items are not scheduled', () async {
    await seed();
    await c.read(settingsProvider.notifier).update((s) => s.copyWith(notify: {NotifChannel.reminders.id: false, NotifChannel.study.id: false}));
    final habit = (await c.read(habitRepoProvider).all()).single;
    await c.read(habitRepoProvider).setDone(habit.habit.id!, D.addDays(D.today(), 1), true);
    final plan = await c.read(_planner).plan();
    expect(plan.where((p) => p.channel == NotifChannel.reminders), isEmpty);
    expect(plan.where((p) => p.channel == NotifChannel.study), isEmpty);
    final habitDays = plan.where((p) => p.channel == NotifChannel.habits).map((p) => D.dayKey(p.at)).toSet();
    expect(habitDays.contains(D.dayKey(D.addDays(D.today(), 1))), isFalse);
  });

  test('cap limits total scheduled notifications', () async {
    for (var k = 0; k < 40; k++) {
      await c
          .read(reminderRepoProvider)
          .save(
            Reminder(
              title: 'R$k',
              dueAt: DateTime.now().add(Duration(hours: 1 + k)),
              recurrence: Recurrence.daily,
              createdAt: DateTime.now(),
            ),
          );
    }
    final plan = await NotificationPlanner(c.read(_planner).ref, maxTotal: 100).plan();
    expect(plan.length, 100);
  });
}
