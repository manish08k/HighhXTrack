import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/states.dart';
import '../../data/models/gym.dart';
import '../shell/nav.dart';
import 'exercise_detail.dart';
import 'exercise_widgets.dart';
import 'gym_providers.dart';

/// Exercises of one muscle group.
class MuscleScreen extends ConsumerWidget {
  const MuscleScreen({super.key, required this.muscle});
  final Muscle muscle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(exercisesProvider((muscle, '')));
    return Scaffold(
      appBar: AppBar(title: Text(muscle.label)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'muscle-fab',
        onPressed: () => editExercise(context, ref, muscle: muscle),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Exercise'),
      ),
      body: AsyncBody<List<Exercise>>(
        value: list,
        builder: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.fitness_center_rounded,
              color: muscle.color,
              title: 'No ${muscle.label.toLowerCase()} exercises',
              actionLabel: 'Add exercise',
              onAction: () => editExercise(context, ref, muscle: muscle),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
            itemBuilder: (context, i) {
              final e = items[i];
              return AppCard(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
                onTap: () => push(context, ExerciseDetailScreen(exerciseId: e.id!)),
                child: Row(
                  children: [
                    IconBadge(Icons.fitness_center_rounded, muscle.color, size: 38),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name, style: context.text.titleSmall),
                          Text([if (e.isCustom) 'Custom', 'Rest ${e.restSeconds}s'].join(' · '), style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.colors.onSurfaceVariant),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
