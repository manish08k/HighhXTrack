import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/gym.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'exercise_widgets.dart';
import 'gym_providers.dart';
import 'rest_timer_bar.dart';
import 'workout_session.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});
  final int exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = ref.watch(exerciseProvider(exerciseId));
    final stats = ref.watch(exerciseStatsProvider(exerciseId));
    final active = ref.watch(activeWorkoutProvider).value;
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));

    return AsyncBody<Exercise?>(
      value: ex,
      loading: const Scaffold(body: LoadingView()),
      builder: (e) {
        if (e == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off_rounded, title: 'Exercise not found'),
          );
        }
        final s = stats.value ?? const ExerciseStats();
        return Scaffold(
          appBar: AppBar(
            title: Text(e.name),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => editExercise(context, ref, existing: e),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (!await confirmDialog(
                    context,
                    title: 'Delete "${e.name}"?',
                    message: s.history.isEmpty ? null : 'Your logged history for this exercise is kept.',
                  )) {
                    return;
                  }
                  await ref.read(gymRepoProvider).deleteExercise(e.id!);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'ex-fab',
            icon: Icon(active == null ? Icons.play_arrow_rounded : Icons.add_rounded),
            label: Text(active == null ? 'Start with this' : 'Add to workout'),
            onPressed: () async {
              final repo = ref.read(gymRepoProvider);
              final id = active?.id ?? await repo.startWorkout(name: '${e.muscle.label} workout');
              await repo.addExercise(id, e.id!);
              if (context.mounted) push(context, const WorkoutSessionScreen());
            },
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
            children: [
              Wrap(
                spacing: Gap.sm,
                children: [
                  Pill(e.muscle.label, color: e.muscle.color),
                  Pill('Rest ${restLabel(e.restSeconds)}', icon: Icons.timer_outlined),
                  if (e.isCustom) const Pill('Custom'),
                ],
              ),
              const SizedBox(height: Gap.lg),
              StatGrid(
                padding: EdgeInsets.zero,
                children: [
                  StatTile(
                    label: 'Personal record',
                    icon: Icons.emoji_events_outlined,
                    color: AppModule.gym.color,
                    value: s.bestWeight == 0 ? '—' : fmtWeight(s.bestWeight, unit),
                    caption: s.bestWeight == 0 ? 'No sets yet' : '× ${s.bestWeightReps} reps',
                  ),
                  StatTile(
                    label: 'Est. 1RM',
                    icon: Icons.trending_up_rounded,
                    value: s.best1rm == 0 ? '—' : fmtWeight(s.best1rm, unit),
                    caption: 'Epley formula',
                  ),
                  StatTile(
                    label: 'Best set volume',
                    icon: Icons.stacked_bar_chart_rounded,
                    value: s.bestVolumeSet == 0 ? '—' : fmtWeight(s.bestVolumeSet, unit),
                    caption: 'weight × reps',
                  ),
                  StatTile(
                    label: 'Sessions',
                    icon: Icons.event_repeat_rounded,
                    value: '${s.history.length}',
                    caption: s.lastDate == null ? 'Never done' : 'Last ${D.relativeDay(s.lastDate!)}',
                  ),
                ],
              ),
              const SectionHeader('Previous performance', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
              AppCard(
                child: s.lastSets.isEmpty
                    ? Text('Complete a set to see your last performance here.', style: context.text.bodyMedium)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (s.lastDate != null)
                            Text(D.relativeDay(s.lastDate!), style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                          const SizedBox(height: Gap.sm),
                          for (var k = 0; k < s.lastSets.length; k++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  SizedBox(width: 56, child: Text('Set ${k + 1}', style: context.text.bodySmall)),
                                  Text(
                                    '${fmtWeight(s.lastSets[k].weight, unit)} × ${s.lastSets[k].reps}',
                                    style: context.text.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: Gap.lg),
              ChartCard(
                title: 'Weight progression',
                subtitle: 'Heaviest set per session',
                child: TimeLineChart(points: [for (final h in s.history) (h.$1, h.$2)], color: AppModule.gym.color, unit: ' $unit'),
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Volume progression',
                subtitle: 'Total weight × reps per session',
                child: TimeLineChart(points: [for (final h in s.history) (h.$1, h.$3)], color: Muscle.back.color, unit: ' $unit'),
              ),
              if (e.notes.isNotEmpty) ...[
                const SectionHeader('Notes', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
                AppCard(child: Text(e.notes, style: context.text.bodyMedium)),
              ],
            ],
          ),
        );
      },
    );
  }
}
