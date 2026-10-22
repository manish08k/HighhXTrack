import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newone/core/modules.dart';
import 'package:newone/core/utils/dates.dart';
import 'package:newone/core/utils/format.dart';
import 'package:newone/core/utils/recurrence.dart';
import 'package:newone/data/db/app_database.dart';
import 'package:newone/data/models/gym.dart';
import 'package:newone/data/models/knowledge.dart';
import 'package:newone/data/models/money.dart';
import 'package:newone/data/models/planner.dart';
import 'package:newone/data/models/todo.dart';
import 'package:newone/data/repositories/note_repo.dart';
import 'package:newone/data/repositories/study_repo.dart';
import 'package:newone/data/repositories/todo_repo.dart';
import 'package:newone/services/backup_service.dart';
import 'package:newone/state/providers.dart';
import 'package:newone/state/services.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    setUpTempPaths();
    db = await openTestDb();
    c = await makeContainer(db);
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('seed data is present', () async {
    final ex = await c.read(gymRepoProvider).exerciseCounts();
    expect(ex.length, Muscle.values.length);
    expect((await c.read(gymRepoProvider).exercises(muscle: Muscle.chest)).map((e) => e.name), contains('Bench Press'));
    final cats = await c.read(moneyRepoProvider).categories(kind: TxKind.expense);
    expect(cats.map((e) => e.name), containsAll(['Food', 'Transport', 'Shopping', 'Bills', 'Entertainment', 'Health', 'Education', 'Gym', 'Other']));
  });

  group('todo', () {
    test('recurring completion spawns next occurrence and undo reverts', () async {
      final repo = c.read(todoRepoProvider);
      final now = DateTime.now();
      final due = DateTime(now.year, now.month, now.day, 10);
      final id = await repo.save(Todo(title: 'Water plants', dueAt: due, hasTime: true, recurrence: Recurrence.daily, createdAt: now, updatedAt: now), [
        const Subtask(title: 'Balcony'),
        const Subtask(title: 'Kitchen', done: true),
      ]);
      final t = (await repo.get(id))!;
      expect(t.subtasks.length, 2);

      final spawned = await repo.setCompleted(t, true);
      expect(spawned, isNotNull);
      final next = (await repo.get(spawned!))!;
      expect(next.dueAt, DateTime(now.year, now.month, now.day + 1, 10));
      expect(next.completed, isFalse);
      expect(next.subtasks.every((s) => !s.done), isTrue);
      expect(next.recurrence, Recurrence.daily);
      expect((await repo.get(id))!.recurrence.isNone, isTrue);

      await repo.undoComplete(t, spawned);
      expect(await repo.get(spawned), isNull);
      final restored = (await repo.get(id))!;
      expect(restored.completed, isFalse);
      expect(restored.recurrence, Recurrence.daily);
    });

    test('views, search, delete/restore and progress', () async {
      final repo = c.read(todoRepoProvider);
      final now = DateTime.now();
      await repo.save(Todo(title: 'Today task', dueAt: D.today(), createdAt: now, updatedAt: now), []);
      await repo.save(Todo(title: 'Overdue task', dueAt: D.addDays(D.today(), -2), createdAt: now, updatedAt: now), []);
      final upId = await repo.save(Todo(title: 'Future task', dueAt: D.addDays(D.today(), 3), createdAt: now, updatedAt: now), []);
      expect((await repo.query(const TodoQuery(view: TodoView.today))).length, 2);
      expect((await repo.query(const TodoQuery(view: TodoView.upcoming))).single.id, upId);
      expect((await repo.query(const TodoQuery(view: TodoView.all, search: 'future'))).length, 1);

      final snap = await repo.delete(upId);
      expect(await repo.get(upId), isNull);
      await repo.restore(snap!);
      expect((await repo.get(upId))!.title, 'Future task');

      final today = (await repo.query(const TodoQuery(view: TodoView.today))).first;
      await repo.setCompleted(today, true);
      expect(await repo.todayProgress(), (1, 2));
    });
  });

  group('reminders', () {
    test('recurring reminder rolls forward and logs history', () async {
      final repo = c.read(reminderRepoProvider);
      final due = DateTime.now().subtract(const Duration(hours: 1));
      final id = await repo.save(
        Reminder(title: 'Pay rent', dueAt: due, recurrence: Recurrence.monthly, createdAt: DateTime.now(), linkModule: AppModule.money),
      );
      final r = (await repo.get(id))!;
      final undo = await repo.complete(r);
      final after = (await repo.get(id))!;
      expect(after.completed, isFalse);
      expect(after.dueAt.isAfter(DateTime.now()), isTrue);
      expect((await repo.history()).length, 1);

      await repo.undo(undo);
      expect((await repo.get(id))!.dueAt, r.dueAt);
      expect(await repo.history(), isEmpty);
    });

    test('one-time reminder completes', () async {
      final repo = c.read(reminderRepoProvider);
      final id = await repo.save(Reminder(title: 'Call mom', dueAt: DateTime.now().add(const Duration(hours: 2)), createdAt: DateTime.now()));
      await repo.complete((await repo.get(id))!);
      expect((await repo.get(id))!.completed, isTrue);
      expect(await repo.active(), isEmpty);
    });

    test('occurrences expand recurring series including snoozed instance', () async {
      final repo = c.read(reminderRepoProvider);
      final start = DateTime.now().add(const Duration(hours: 1));
      await repo.save(Reminder(title: 'Stretch', dueAt: start, recurrence: Recurrence.daily, createdAt: DateTime.now()));
      final occ = await repo.occurrences(DateTime.now(), DateTime.now().add(const Duration(days: 3)));
      expect(occ.length, 3);
    });
  });

  group('money', () {
    test('summary, budgets and recurring processing', () async {
      final repo = c.read(moneyRepoProvider);
      final food = (await repo.categories(kind: TxKind.expense)).firstWhere((x) => x.name == 'Food');
      final now = DateTime.now();
      await repo.save(Txn(kind: TxKind.expense, amount: 42000, categoryId: food.id, date: now, createdAt: now));
      await repo.save(Txn(kind: TxKind.income, amount: 5000000, date: now, createdAt: now));
      final s = await repo.summary(now, budget: 2000000);
      expect(s.spentToday, 42000);
      expect(s.expense, 42000);
      expect(s.income, 5000000);
      expect(s.remaining, 2000000 - 42000);
      expect(s.byCategory[food.id], 42000);

      // Weekly bill whose anchor was 3 weeks ago → 4 occurrences created.
      final anchor = D.addDays(D.today(), -21);
      await repo.saveRecurring(RecurringTxn(title: 'Gym fee', amount: 10000, recurrence: Recurrence.weekly, anchor: anchor, next: anchor));
      final created = await repo.processDue();
      expect(created, 4);
      expect(await repo.processDue(), 0, reason: 'idempotent');
      final r = (await repo.recurring()).single;
      expect(r.next.isAfter(DateTime.now()), isTrue);
    });

    test('money parse/format', () {
      expect(Money.parse('1,250.50'), 125050);
      expect(Money.parse(''), isNull);
    });
  });

  group('habits', () {
    test('streaks and completion', () async {
      final repo = c.read(habitRepoProvider);
      final id = await repo.save(Habit(name: 'Read', icon: 20, color: 0xFF000000, createdAt: D.addDays(D.today(), -10)));
      for (var k = 1; k <= 4; k++) {
        await repo.setDone(id, D.addDays(D.today(), -k), true);
      }
      var h = (await repo.get(id))!;
      expect(h.currentStreak, 4, reason: 'today not yet done does not break the streak');
      await repo.setDone(id, D.today(), true);
      h = (await repo.get(id))!;
      expect(h.currentStreak, 5);
      expect(h.bestStreak, 5);
      expect(h.doneToday, isTrue);
      await repo.setDone(id, D.addDays(D.today(), -2), false);
      h = (await repo.get(id))!;
      expect(h.currentStreak, 2);
      expect(h.bestStreak, 2);
    });
  });

  group('gym', () {
    test('workout session, sets, PRs and prefill from history', () async {
      final repo = c.read(gymRepoProvider);
      final bench = (await repo.exercises(search: 'Bench Press')).firstWhere((e) => e.name == 'Bench Press');
      final wid = await repo.startWorkout(name: 'Push Day');
      await repo.addExercise(wid, bench.id!);
      var w = (await repo.activeWorkout())!;
      final sets = w.exercises.single.sets;
      expect(sets.length, 3);
      await repo.updateSet(sets[0].id!, weight: 60, reps: 10);
      await repo.setStatus(sets[0].id!, SetStatus.done);
      await repo.updateSet(sets[1].id!, weight: 70, reps: 6);
      await repo.setStatus(sets[1].id!, SetStatus.done);
      await repo.setStatus(sets[2].id!, SetStatus.skipped);
      await repo.finishWorkout(wid);
      expect(await repo.activeWorkout(), isNull);
      w = (await repo.workout(wid))!;
      expect(w.totalSets, 2);
      expect(w.volume, 60 * 10 + 70 * 6);

      final stats = await repo.exerciseStats(bench.id!);
      expect(stats.bestWeight, 70);
      expect(stats.lastSets.length, 2);

      // Next session prefills from the previous one.
      final w2 = await repo.startWorkout(name: 'Push Day 2');
      await repo.addExercise(w2, bench.id!);
      final prefilled = (await repo.activeWorkout())!.exercises.single.sets;
      expect(prefilled.map((s) => s.weight), [60, 70]);
      expect((await repo.overview()).total, 1);
    });

    test('body metrics history', () async {
      final repo = c.read(gymRepoProvider);
      await repo.addBodyMetric('Weight', 80, DateTime(2026, 1, 1));
      await repo.addBodyMetric('Weight', 78.5, DateTime(2026, 2, 1));
      await repo.addBodyMetric('Neck', 38, DateTime(2026, 2, 1));
      expect((await repo.bodyMetrics('Weight')).map((m) => m.value), [80, 78.5]);
      expect((await repo.latestBody())['Weight']!.value, 78.5);
      expect(await repo.bodyKinds(), contains('Neck'));
    });
  });

  group('notes & study & search', () {
    test('notes with folders, tags, checklist, archive', () async {
      final repo = c.read(noteRepoProvider);
      final folder = await repo.saveFolder(null, 'Ideas');
      final now = DateTime.now();
      final id = await repo.save(
        Note(
          title: 'Groceries',
          checklist: [ChecklistItem('Milk', done: true), ChecklistItem('Eggs')],
          folderId: folder,
          tags: ['home'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect((await repo.query(NoteQuery(folderId: folder))).single.checklist.first.done, isTrue);
      expect((await repo.query(const NoteQuery(tag: 'home'))).length, 1);
      await repo.setFlags(id, archived: true);
      expect(await repo.query(const NoteQuery()), isEmpty);
      expect((await repo.query(const NoteQuery(archived: true))).length, 1);
    });

    test('study subjects, topics, sessions and streak', () async {
      final repo = c.read(studyRepoProvider);
      final sid = await repo.saveSubject(Subject(name: 'DSA', color: 0xFF14A3B8, createdAt: DateTime.now()));
      final arrays = await repo.saveTopic(subjectId: sid, name: 'Arrays');
      await repo.saveTopic(subjectId: sid, name: 'Graphs');
      await repo.setTopicDone(arrays, true);
      await repo.addSession(StudySession(subjectId: sid, startedAt: DateTime.now().subtract(const Duration(hours: 1)), durationSec: 3600));
      await repo.addSession(StudySession(subjectId: sid, startedAt: D.addDays(DateTime.now(), -1), durationSec: 1800));
      final s = (await repo.subject(sid))!;
      expect(s.topicsDone, 1);
      expect(s.topicCount, 2);
      expect(s.totalSeconds, 5400);
      expect(studyStreak(await repo.dayTotals()), 2);
      expect(await repo.topicCompletion(), (1, 2));
    });

    test('global search groups by module', () async {
      final now = DateTime.now();
      await c.read(todoRepoProvider).save(Todo(title: 'Renew passport', createdAt: now, updatedAt: now), []);
      await c.read(documentRepoProvider).save(Doc(name: 'Passport', category: 'Passport', expiryAt: D.addDays(now, 20), createdAt: now));
      final res = await c.read(searchRepoProvider).search('passport');
      expect(res.keys, containsAll([AppModule.todo, AppModule.documents]));
      final doc = (await c.read(documentRepoProvider).all()).single;
      expect(doc.status, DocStatus.expiring);
    });
  });

  test('backup and restore round-trip', () async {
    final now = DateTime.now();
    await c.read(todoRepoProvider).save(Todo(title: 'Backed up task', createdAt: now, updatedAt: now), [const Subtask(title: 'step')]);
    final svc = c.read(backupServiceProvider);
    final backup = await svc.buildBackup();
    final bytes = await svc.backupBytes();
    final parsed = svc.parse(bytes);

    // Wipe a table, then restore.
    await db.db.delete('todos');
    expect(await c.read(todoRepoProvider).query(const TodoQuery(view: TodoView.all)), isEmpty);
    final res = await svc.restore(parsed);
    expect(res.rows, greaterThan(50));
    final todos = await c.read(todoRepoProvider).query(const TodoQuery(view: TodoView.all));
    expect(todos.single.title, 'Backed up task');
    expect(todos.single.subtasks.single.title, 'step');
    expect(backup['format'], 'highhxtrack-backup');
    expect(() => svc.parse(Uint8List.fromList(utf8.encode('not json'))), throwsA(isA<BackupException>()));
  });
}
