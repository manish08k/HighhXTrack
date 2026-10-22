import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/gym.dart';
import '../../state/providers.dart';
import '../../state/timers.dart';
import '../shell/nav.dart';
import 'exercise_detail.dart';
import 'exercise_widgets.dart';
import 'gym_progress.dart';
import 'gym_providers.dart';
import 'muscle_screen.dart';
import 'rest_timer_bar.dart';
import 'routine_editor.dart';
import 'workout_detail.dart';
import 'workout_session.dart';

class GymScreen extends ConsumerWidget {
  const GymScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gym'),
          actions: [
            IconButton(
              tooltip: 'Find exercise',
              icon: const Icon(Icons.search_rounded),
              onPressed: () async {
                final e = await pickExercise(context);
                if (e != null && context.mounted) push(context, ExerciseDetailScreen(exerciseId: e.id!));
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Train'),
              Tab(text: 'Muscles'),
              Tab(text: 'Progress'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: const TabBarView(children: [_TrainTab(), _MusclesTab(), GymProgressView(), _HistoryTab()]),
      ),
    );
  }
}

Future<void> startWorkout(BuildContext context, WidgetRef ref, {Routine? routine}) async {
  final active = await ref.read(gymRepoProvider).activeWorkout();
  if (!context.mounted) return;
  if (active != null) {
    showSnack(context, 'Resuming your workout in progress');
  } else {
    await guard(context, () => ref.read(gymRepoProvider).startWorkout(name: routine?.name ?? 'Workout', routine: routine));
  }
  if (context.mounted) push(context, const WorkoutSessionScreen());
}

class _TrainTab extends ConsumerWidget {
  const _TrainTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkoutProvider).value;
    final today = ref.watch(todayRoutineProvider).value;
    final routines = ref.watch(routinesProvider);
    final days = ref.watch(workoutDaysProvider).value ?? const <int>{};
    final c = AppModule.gym.color;
    final rest = ref.watch(restTimerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, 96),
      children: [
        if (active != null) ...[
          AppCard(
            color: c.withValues(alpha: 0.12),
            borderColor: c.withValues(alpha: 0.4),
            onTap: () => push(context, const WorkoutSessionScreen()),
            child: Row(
              children: [
                IconBadge(Icons.play_arrow_rounded, c, size: 44),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Workout in progress', style: context.text.labelMedium!.copyWith(color: c)),
                      Text(active.name, style: context.text.titleMedium),
                      Text('${active.totalSets} sets · started ${D.time(active.startedAt)}', style: context.text.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          if (rest.active) ...[const SizedBox(height: Gap.sm), RestTimerBar(compact: true, onTap: () => push(context, const WorkoutSessionScreen()))],
          const SizedBox(height: Gap.md),
        ],
        _WeekStrip(days: days),
        const SizedBox(height: Gap.md),
        if (active == null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Today's workout", style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(today?.name ?? 'Rest day or free training', style: context.text.titleLarge),
                if (today != null)
                  Text(
                    '${today.items.length} exercises · ${today.items.map((e) => e.muscle?.label).whereType<String>().toSet().join(', ')}',
                    style: context.text.bodySmall,
                  ),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    if (today != null) ...[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => startWorkout(context, ref, routine: today),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text('Start ${today.name}'),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                    ],
                    Expanded(
                      child: today == null
                          ? FilledButton.tonalIcon(
                              onPressed: () => startWorkout(context, ref),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Empty workout'),
                            )
                          : OutlinedButton.icon(onPressed: () => startWorkout(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('Empty')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        SectionHeader(
          'Routines',
          action: 'New',
          onAction: () => push(context, const RoutineEditorScreen()),
          padding: const EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.xs),
        ),
        AsyncBody<List<Routine>>(
          value: routines,
          compact: true,
          builder: (list) {
            if (list.isEmpty) {
              return AppCard(
                onTap: () => push(context, const RoutineEditorScreen()),
                child: Row(
                  children: [
                    IconBadge(Icons.view_list_rounded, c),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Text('Create routines like Push, Pull and Legs, schedule them on weekdays and get reminders.', style: context.text.bodyMedium),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final r in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.xs, Gap.md),
                      onTap: () => push(context, RoutineEditorScreen(routine: r)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name, style: context.text.titleSmall),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    '${r.items.length} exercises',
                                    if (r.weekdays.isNotEmpty) (r.weekdays.toList()..sort()).map(D.weekdayName).join(' '),
                                    if (r.remindMinutes != null && r.weekdays.isNotEmpty) '⏰ ${D.minutesOfDayLabel(r.remindMinutes!)}',
                                  ].join(' · '),
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Start ${r.name}',
                            onPressed: () => startWorkout(context, ref, routine: r),
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days});
  final Set<int> days;

  @override
  Widget build(BuildContext context) {
    final start = D.startOfWeek(DateTime.now());
    final c = AppModule.gym.color;
    final count = [for (var k = 0; k < 7; k++) D.addDays(start, k)].where((d) => days.contains(D.dayKey(d))).length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week · $count ${count == 1 ? 'workout' : 'workouts'}', style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: Gap.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var k = 0; k < 7; k++)
                Builder(
                  builder: (context) {
                    final d = D.addDays(start, k);
                    final done = days.contains(D.dayKey(d));
                    final isToday = D.sameDay(d, DateTime.now());
                    return Column(
                      children: [
                        Text(D.weekdayLetter(d.weekday), style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done ? c : context.colors.surfaceContainerHigh,
                            border: isToday ? Border.all(color: c, width: 2) : null,
                          ),
                          child: done ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : Text('${d.day}', style: context.text.labelMedium),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MusclesTab extends ConsumerWidget {
  const _MusclesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(exerciseCountsProvider).value ?? const {};
    return LayoutBuilder(
      builder: (context, cons) {
        final cols = cons.maxWidth > 600 ? 4 : 2;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: Gap.md,
            crossAxisSpacing: Gap.md,
            childAspectRatio: 1.45,
          ),
          itemCount: Muscle.values.length,
          itemBuilder: (context, i) {
            final m = Muscle.values[i];
            return AppCard(
              onTap: () => push(context, MuscleScreen(muscle: m)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(Icons.fitness_center_rounded, m.color, size: 36),
                  const Spacer(),
                  Text(m.label, style: context.text.titleMedium),
                  Text('${counts[m] ?? 0} exercises', style: context.text.bodySmall),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    return AsyncBody<List<Workout>>(
      value: ref.watch(workoutHistoryProvider),
      builder: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.history_rounded,
            color: AppModule.gym.color,
            title: 'No workouts yet',
            message: 'Finished workouts appear here.',
            actionLabel: 'Start a workout',
            onAction: () => startWorkout(context, ref),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, 96),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
          itemBuilder: (context, i) {
            final w = list[i];
            final muscles = {for (final e in w.exercises) e.exercise.muscle};
            return AppCard(
              onTap: () => push(context, WorkoutDetailScreen(workoutId: w.id!)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(w.name, style: context.text.titleSmall)),
                      Text(D.relativeDay(w.startedAt), style: context.text.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${D.duration(w.duration)} · ${w.totalSets} sets · ${fmtWeight(w.volume, unit)}', style: context.text.bodySmall),
                  if (muscles.isNotEmpty) ...[
                    const SizedBox(height: Gap.sm),
                    Wrap(spacing: 6, runSpacing: 4, children: [for (final m in muscles) Pill(m.label, color: m.color, dense: true)]),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
