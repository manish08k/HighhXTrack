import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/states.dart';
import '../../data/models/gym.dart';
import '../../data/repositories/gym_repo.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'body_screen.dart';
import 'exercise_detail.dart';
import 'gym_providers.dart';

/// Gym progress dashboard (embedded as a tab in the Gym screen).
class GymProgressView extends ConsumerWidget {
  const GymProgressView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ov = ref.watch(gymOverviewProvider);
    final weekly = ref.watch(gymWeeklyProvider).value ?? const [];
    final freq = ref.watch(muscleFrequencyProvider).value ?? const {};
    final prs = ref.watch(personalRecordsProvider).value ?? const [];
    final weight = ref.watch(bodyMetricsProvider(BodyKind.weight)).value ?? const <BodyMetric>[];
    final latest = ref.watch(latestBodyProvider).value ?? const {};
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final c = AppModule.gym.color;

    return AsyncBody<GymOverview>(
      value: ov,
      builder: (o) => ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, 96),
        children: [
          StatGrid(
            padding: EdgeInsets.zero,
            children: [
              StatTile(label: 'Total workouts', icon: Icons.fitness_center_rounded, value: '${o.total}', color: c),
              StatTile(label: 'This week', icon: Icons.date_range_rounded, value: '${o.thisWeek}'),
              StatTile(label: 'This month', icon: Icons.calendar_month_outlined, value: '${o.thisMonth}'),
              StatTile(label: 'Avg duration', icon: Icons.timer_outlined, value: o.total == 0 ? '—' : D.duration(o.avgDuration)),
            ],
          ),
          const SizedBox(height: Gap.md),
          ChartCard(
            title: 'Workout frequency',
            subtitle: 'Workouts per week · last 12 weeks',
            child: SimpleBarChart(
              values: [for (final w in weekly) w.$2.toDouble()],
              labels: [for (final w in weekly) D.dayMonth(w.$1)],
              color: c,
              highlightLast: true,
            ),
          ),
          const SizedBox(height: Gap.md),
          ChartCard(
            title: 'Weekly volume',
            subtitle: 'Total $unit lifted (weight × reps)',
            child: SimpleBarChart(
              values: [for (final w in weekly) w.$3],
              labels: [for (final w in weekly) D.dayMonth(w.$1)],
              color: Muscle.back.color,
              highlightLast: true,
              format: (v) => v >= 1000 ? '${trimNum(v / 1000)}k' : trimNum(v),
            ),
          ),
          const SizedBox(height: Gap.md),
          ChartCard(
            title: 'Workout duration',
            subtitle: 'Average minutes per workout, by week',
            child: SimpleBarChart(
              values: [for (final w in weekly) w.$4],
              labels: [for (final w in weekly) D.dayMonth(w.$1)],
              color: Muscle.legs.color,
              highlightLast: true,
            ),
          ),
          const SizedBox(height: Gap.md),
          ChartCard(
            title: 'Muscle-group frequency',
            subtitle: 'Sessions in the last 30 days',
            child: RankedBars(
              items: [
                for (final m in (Muscle.values.toList()..sort((a, b) => (freq[b] ?? 0).compareTo(freq[a] ?? 0))))
                  if ((freq[m] ?? 0) > 0) (m.label, (freq[m] ?? 0).toDouble(), m.color, null),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          ChartCard(
            title: 'Body weight',
            subtitle: latest[BodyKind.weight] == null ? 'No entries yet' : 'Latest ${trimNum(latest[BodyKind.weight]!.value)} $unit',
            trailing: TextButton(onPressed: () => push(context, const BodyScreen()), child: const Text('Body')),
            child: TimeLineChart(points: [for (final m in weight) (m.measuredAt, m.value)], color: c, unit: ' $unit'),
          ),
          const SizedBox(height: Gap.md),
          AppCard(
            onTap: () => push(context, const BodyScreen(initialKind: 'Waist')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Body measurements', style: context.text.titleSmall),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    for (final k in BodyKind.builtIn.skip(1)) Pill('$k ${latest[k] == null ? '—' : '${trimNum(latest[k]!.value)} cm'}'),
                    for (final e in latest.entries.where((e) => !BodyKind.builtIn.contains(e.key))) Pill('${e.key} ${trimNum(e.value.value)}'),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Personal records', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
          if (prs.isEmpty)
            const EmptyState(icon: Icons.emoji_events_outlined, title: 'No records yet', message: 'Complete sets to set your first PRs.', compact: true)
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              child: Column(
                children: [
                  for (final (e, w, reps) in prs)
                    ListTile(
                      leading: Dot(e.muscle.color, size: 10),
                      title: Text(e.name),
                      subtitle: Text(e.muscle.label),
                      trailing: Text('${fmtWeight(w, unit)} × $reps', style: context.text.titleSmall),
                      onTap: () => push(context, ExerciseDetailScreen(exerciseId: e.id!)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
