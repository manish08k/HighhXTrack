import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/icon_set.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/swipe.dart';
import '../../data/models/planner.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'habit_detail.dart';
import 'habit_editor.dart';
import 'habit_providers.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final totals = ref.watch(habitDailyTotalsProvider).value ?? const {};
    final c = AppModule.habits.color;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        actions: [
          IconButton(tooltip: 'Archived habits', icon: const Icon(Icons.inventory_2_outlined), onPressed: () => push(context, const _ArchivedHabitsScreen())),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'habit-fab',
        tooltip: 'New habit',
        onPressed: () => push(context, const HabitEditorScreen()),
        child: const Icon(Icons.add_rounded),
      ),
      body: AsyncBody<List<HabitStats>>(
        value: habits,
        onRetry: () => ref.invalidate(habitsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.local_fire_department_outlined,
              color: c,
              title: 'Build your first habit',
              message: 'Small daily actions add up. Track streaks and consistency here.',
              actionLabel: 'Create habit',
              onAction: () => push(context, const HabitEditorScreen()),
            );
          }
          final (done, due) = todayHabitProgress(list);
          final bestCurrent = list.map((h) => h.currentStreak).fold(0, (a, b) => b > a ? b : a);
          final best = list.map((h) => h.bestStreak).fold(0, (a, b) => b > a ? b : a);
          final week = list.isEmpty ? 0.0 : list.map((h) => h.weekRate).reduce((a, b) => a + b) / list.length;
          final month = list.isEmpty ? 0.0 : list.map((h) => h.monthRate).reduce((a, b) => a + b) / list.length;
          final today = DateTime.now();
          final todays = list.where((h) => h.habit.scheduledOn(today)).toList();
          final others = list.where((h) => !h.habit.scheduledOn(today)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
            children: [
              AppCard(
                child: Row(
                  children: [
                    ProgressRing(
                      value: due == 0 ? 0 : done / due,
                      size: 64,
                      color: c,
                      child: Text('$done/$due', style: context.text.labelLarge),
                    ),
                    const SizedBox(width: Gap.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today's habits", style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                          Text(
                            due == 0 ? 'Nothing scheduled' : (done == due ? 'All done — great job!' : '${due - done} left today'),
                            style: context.text.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              StatGrid(
                padding: EdgeInsets.zero,
                children: [
                  StatTile(label: 'Current streak', icon: Icons.local_fire_department_rounded, value: '$bestCurrent', caption: 'days (best habit)', color: c),
                  StatTile(label: 'Best streak', icon: Icons.emoji_events_outlined, value: '$best', caption: 'all time'),
                  StatTile(label: 'This week', icon: Icons.date_range_rounded, value: pct(week), caption: 'completion'),
                  StatTile(label: 'Last 30 days', icon: Icons.calendar_month_outlined, value: pct(month), caption: 'completion'),
                ],
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Consistency',
                subtitle: 'Habits completed per day',
                child: HeatmapCalendar(values: totals, weeks: 26, color: c, label: (d, v) => '${D.dayMonth(d)}: ${v.toInt()} done'),
              ),
              const SectionHeader('Today', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
              if (todays.isEmpty) Text('No habits scheduled today.', style: context.text.bodyMedium),
              for (final h in todays)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: HabitTile(h: h),
                ),
              if (others.isNotEmpty) ...[
                const SectionHeader('Not scheduled today', padding: EdgeInsets.fromLTRB(0, Gap.lg, 0, Gap.sm)),
                for (final h in others)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: HabitTile(h: h),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class HabitTile extends ConsumerWidget {
  const HabitTile({super.key, required this.h, this.swipe = true});
  final HabitStats h;
  final bool swipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = h.habit.colorValue;
    final done = h.doneToday;
    final ws = D.startOfWeek(DateTime.now());
    final tile = AppCard(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.sm, Gap.md),
      onTap: () => push(context, HabitDetailScreen(habitId: h.habit.id!)),
      child: Row(
        children: [
          IconBadge(iconAt(h.habit.icon), c, size: 44),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.habit.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded, size: 14, color: h.currentStreak > 0 ? Palette.warning : context.colors.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text(
                      h.habit.schedule == HabitSchedule.weekly
                          ? '${h.currentStreak} wk · ${h.doneThisWeek}/${h.habit.weeklyTarget} this week'
                          : '${h.currentStreak} day streak',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var k = 0; k < 7; k++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: h.doneOn(D.addDays(ws, k))
                                ? c
                                : (h.habit.scheduledOn(D.addDays(ws, k)) ? context.colors.surfaceContainerHighest : Colors.transparent),
                            border: h.habit.scheduledOn(D.addDays(ws, k)) ? null : Border.all(color: context.colors.outlineVariant),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            checked: done,
            label: done ? 'Mark ${h.habit.name} not done' : 'Complete ${h.habit.name}',
            child: InkResponse(
              onTap: () => toggleHabit(context, ref, h),
              radius: 28,
              child: AnimatedContainer(
                duration: Durations2.normal,
                curve: Curves.easeOutBack,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? c : Colors.transparent,
                  border: Border.all(color: c, width: 2.5),
                ),
                child: Icon(Icons.check_rounded, color: done ? Colors.white : c.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ],
      ),
    );
    if (!swipe) return tile;
    return SwipeTile(
      key: ValueKey('habit-${h.habit.id}-$done'),
      start: SwipeAction(
        icon: done ? Icons.undo_rounded : Icons.check_rounded,
        label: done ? 'Undo' : 'Complete',
        color: done ? context.colors.onSurfaceVariant : Palette.success,
        onTrigger: () => toggleHabit(context, ref, h),
      ),
      child: tile,
    );
  }
}

class _ArchivedHabitsScreen extends ConsumerWidget {
  const _ArchivedHabitsScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived habits')),
      body: AsyncBody<List<HabitStats>>(
        value: ref.watch(archivedHabitsProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'No archived habits')
            : ListView(
                padding: const EdgeInsets.all(Gap.page),
                children: [
                  for (final h in list)
                    ListTile(
                      leading: IconBadge(iconAt(h.habit.icon), h.habit.colorValue),
                      title: Text(h.habit.name),
                      subtitle: Text('Best streak ${h.bestStreak}'),
                      trailing: TextButton(onPressed: () => ref.read(habitRepoProvider).setArchived(h.habit.id!, false), child: const Text('Restore')),
                      onTap: () => push(context, HabitDetailScreen(habitId: h.habit.id!)),
                    ),
                ],
              ),
      ),
    );
  }
}
