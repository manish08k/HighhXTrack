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
import '../shell/nav.dart';
import 'exercise_detail.dart';
import 'gym_providers.dart';
import 'routine_editor.dart';

/// Summary of a finished workout.
class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId, this.justFinished = false});
  final int workoutId;
  final bool justFinished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    return AsyncBody<Workout?>(
      value: ref.watch(workoutProvider(workoutId)),
      loading: const Scaffold(body: LoadingView()),
      builder: (w) {
        if (w == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off_rounded, title: 'Workout not found'),
          );
        }
        final muscles = {for (final e in w.exercises) e.exercise.muscle};
        return Scaffold(
          appBar: AppBar(
            title: Text(justFinished ? 'Workout summary' : w.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'notes':
                      final n = await promptText(context, title: 'Workout notes', initial: w.notes);
                      if (n != null) await ref.read(gymRepoProvider).updateWorkoutNotes(w.id!, n);
                    case 'routine':
                      if (context.mounted) push(context, RoutineEditorScreen(fromWorkout: w));
                    case 'delete':
                      if (context.mounted &&
                          await confirmDialog(context, title: 'Delete workout?', message: 'This removes it from your history and progress.')) {
                        await ref.read(gymRepoProvider).deleteWorkout(w.id!);
                        if (context.mounted) Navigator.pop(context);
                      }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'notes', child: Text('Edit notes')),
                  PopupMenuItem(value: 'routine', child: Text('Save as routine')),
                  PopupMenuItem(value: 'delete', child: Text('Delete workout')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xxxl),
            children: [
              if (justFinished)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.lg),
                  child: AppCard(
                    color: AppModule.gym.color.withValues(alpha: 0.12),
                    borderColor: Colors.transparent,
                    child: Row(
                      children: [
                        Icon(Icons.emoji_events_rounded, color: AppModule.gym.color, size: 36),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Workout complete!', style: context.text.titleMedium),
                              Text(w.name, style: context.text.bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Text(D.longDate(w.startedAt), style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: Gap.md),
              StatGrid(
                padding: EdgeInsets.zero,
                children: [
                  StatTile(label: 'Duration', icon: Icons.timer_outlined, value: D.duration(w.duration)),
                  StatTile(label: 'Sets', icon: Icons.repeat_rounded, value: '${w.totalSets}'),
                  StatTile(label: 'Volume', icon: Icons.stacked_bar_chart_rounded, value: fmtWeight(w.volume, unit)),
                  StatTile(
                    label: 'Exercises',
                    icon: Icons.fitness_center_rounded,
                    value: '${w.exercises.length}',
                    caption: muscles.map((m) => m.label).join(', '),
                  ),
                ],
              ),
              if (w.notes.isNotEmpty) ...[const SizedBox(height: Gap.md), AppCard(child: Text(w.notes))],
              const SectionHeader('Exercises', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
              for (final e in w.exercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: AppCard(
                    onTap: () => push(context, ExerciseDetailScreen(exerciseId: e.exercise.id!)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Dot(e.exercise.muscle.color, size: 10),
                            const SizedBox(width: Gap.sm),
                            Expanded(child: Text(e.exercise.name, style: context.text.titleSmall)),
                            Text(fmtWeight(e.volume, unit), style: context.text.bodySmall),
                          ],
                        ),
                        const SizedBox(height: Gap.sm),
                        Wrap(
                          spacing: Gap.sm,
                          runSpacing: Gap.xs,
                          children: [for (final s in e.sets.where((s) => s.status == SetStatus.done)) Pill('${fmtWeight(s.weight, unit)} × ${s.reps}')],
                        ),
                        if (e.notes.isNotEmpty) ...[const SizedBox(height: Gap.sm), Text(e.notes, style: context.text.bodySmall)],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
