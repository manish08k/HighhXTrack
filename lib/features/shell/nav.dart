import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../state/providers.dart';
import '../calendar/calendar_screen.dart';
import '../calendar/event_editor.dart';
import '../documents/document_detail.dart';
import '../documents/documents_screen.dart';
import '../gym/exercise_detail.dart';
import '../gym/gym_screen.dart';
import '../gym/workout_detail.dart';
import '../gym/workout_session.dart';
import '../habits/habit_detail.dart';
import '../habits/habits_screen.dart';
import '../money/money_screen.dart';
import '../money/recurring_screen.dart';
import '../money/txn_editor.dart';
import '../notes/note_editor.dart';
import '../notes/notes_screen.dart';
import '../reminders/reminder_editor.dart';
import '../reminders/reminders_screen.dart';
import '../study/study_screen.dart';
import '../study/study_timer_screen.dart';
import '../study/subject_detail.dart';
import '../todo/todo_editor.dart';
import '../todo/todo_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Bottom navigation tabs. Modules not listed here open as pushed pages.
enum NavTab { home, todo, calendar, money, more }

Future<T?> push<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

NavigatorState? get _nav => rootNavigatorKey.currentState;

/// Opens a module's main screen from anywhere.
void openModule(WidgetRef ref, AppModule m) {
  final tab = switch (m) {
    AppModule.todo => NavTab.todo,
    AppModule.calendar => NavTab.calendar,
    AppModule.money => NavTab.money,
    _ => null,
  };
  if (tab != null) {
    _nav?.popUntil((r) => r.isFirst);
    ref.read(tabProvider.notifier).select(tab.index);
    return;
  }
  _nav?.push(MaterialPageRoute(builder: (_) => moduleHome(m)));
}

Widget moduleHome(AppModule m) => switch (m) {
  AppModule.todo => const TodoScreen(standalone: true),
  AppModule.gym => const GymScreen(),
  AppModule.money => const MoneyScreen(standalone: true),
  AppModule.reminders => const RemindersScreen(),
  AppModule.habits => const HabitsScreen(),
  AppModule.calendar => const CalendarScreen(standalone: true),
  AppModule.documents => const DocumentsScreen(),
  AppModule.notes => const NotesScreen(),
  AppModule.study => const StudyScreen(),
};

/// Opens a specific item in its original module.
void openItem(WidgetRef ref, AppModule m, int id, {String? kind, int? parentId}) {
  final nav = _nav;
  if (nav == null) return;
  Widget? page = switch (m) {
    AppModule.todo => TodoEditorScreen(id: id),
    AppModule.gym => switch (kind) {
      'exercise' => ExerciseDetailScreen(exerciseId: id),
      'workout' => WorkoutDetailScreen(workoutId: id),
      'active' => const WorkoutSessionScreen(),
      _ => const GymScreen(),
    },
    AppModule.money => kind == 'recurring' ? const RecurringScreen() : TxnEditorScreen(id: id),
    AppModule.reminders => ReminderEditorScreen(id: id),
    AppModule.habits => HabitDetailScreen(habitId: id),
    AppModule.calendar => EventEditorScreen(id: id),
    AppModule.documents => DocumentDetailScreen(docId: id),
    AppModule.notes => NoteEditorScreen(id: id),
    AppModule.study => switch (kind) {
      'timer' => const StudyTimerScreen(),
      'topic' => parentId == null ? null : SubjectDetailScreen(subjectId: parentId),
      'subject' => SubjectDetailScreen(subjectId: id),
      _ => id > 0 ? SubjectDetailScreen(subjectId: id) : const StudyScreen(),
    },
  };
  if (page != null) nav.push(MaterialPageRoute(builder: (_) => page));
}

/// Handles a notification payload `module:id[:kind]`.
void openPayload(WidgetRef ref, String payload) {
  final parts = payload.split(':');
  final m = AppModule.byName(parts.first);
  if (m == null) return;
  final id = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final kind = parts.length > 2 ? parts[2] : null;
  if (m == AppModule.gym && kind == 'routine') {
    openModule(ref, AppModule.gym);
    return;
  }
  if (m == AppModule.study && kind == null) {
    openModule(ref, AppModule.study);
    return;
  }
  if (id == 0 && kind == null) {
    openModule(ref, m);
    return;
  }
  openItem(ref, m, id, kind: kind);
}
