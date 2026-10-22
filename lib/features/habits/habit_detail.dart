import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/icon_set.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/planner.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'habit_editor.dart';
import 'habit_providers.dart';

class HabitDetailScreen extends ConsumerStatefulWidget {
  const HabitDetailScreen({super.key, required this.habitId});
  final int habitId;
  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  DateTime _month = D.startOfMonth(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return AsyncBody<HabitStats?>(
      value: ref.watch(habitProvider(widget.habitId)),
      loading: const Scaffold(body: LoadingView()),
      builder: (h) {
        if (h == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off_rounded, title: 'Habit not found'),
          );
        }
        final c = h.habit.colorValue;
        return Scaffold(
          appBar: AppBar(
            title: Text(h.habit.name),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => push(context, HabitEditorScreen(habit: h.habit)),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  final repo = ref.read(habitRepoProvider);
                  if (v == 'archive') {
                    await repo.setArchived(h.habit.id!, !h.habit.archived);
                    if (context.mounted) Navigator.pop(context);
                  } else if (v == 'delete') {
                    if (await confirmDialog(
                      context,
                      title: 'Delete habit?',
                      message: 'All completion history for "${h.habit.name}" will be removed. Archive it instead to keep history.',
                    )) {
                      await repo.delete(h.habit.id!);
                      if (context.mounted) Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'archive', child: Text(h.habit.archived ? 'Unarchive' : 'Archive')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xxxl),
            children: [
              Row(
                children: [
                  IconBadge(iconAt(h.habit.icon), c, size: 52),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.habit.scheduleLabel, style: context.text.titleSmall),
                        if (h.habit.remindMinutes != null) Text('Reminder at ${D.minutesOfDayLabel(h.habit.remindMinutes!)}', style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: h.doneToday ? context.colors.surfaceContainerHighest : c,
                      foregroundColor: h.doneToday ? context.colors.onSurface : Colors.white,
                    ),
                    onPressed: () => toggleHabit(context, ref, h),
                    icon: Icon(h.doneToday ? Icons.undo_rounded : Icons.check_rounded),
                    label: Text(h.doneToday ? 'Undo' : 'Done today'),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              StatGrid(
                padding: EdgeInsets.zero,
                children: [
                  StatTile(
                    label: 'Current streak',
                    value: '${h.currentStreak}',
                    caption: h.habit.schedule == HabitSchedule.weekly ? 'weeks' : 'days',
                    color: c,
                    icon: Icons.local_fire_department_rounded,
                  ),
                  StatTile(
                    label: 'Longest streak',
                    value: '${h.bestStreak}',
                    caption: h.habit.schedule == HabitSchedule.weekly ? 'weeks' : 'days',
                    icon: Icons.emoji_events_outlined,
                  ),
                  StatTile(label: 'This week', value: pct(h.weekRate), caption: 'completion', icon: Icons.date_range_rounded),
                  StatTile(label: 'Last 30 days', value: pct(h.monthRate), caption: '${h.days.length} total check-ins', icon: Icons.calendar_month_outlined),
                ],
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'History',
                subtitle: 'Last 6 months',
                child: HeatmapCalendar(
                  values: {for (final d in h.days) d: 1},
                  weeks: 26,
                  color: c,
                  maxValue: 1,
                  label: (d, v) => '${D.dayMonth(d)}: ${v > 0 ? 'done' : 'not done'}',
                ),
              ),
              const SizedBox(height: Gap.md),
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous month',
                          onPressed: () => setState(() => _month = D.addMonths(_month, -1)),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Text(D.monthYear(_month), textAlign: TextAlign.center, style: context.text.titleSmall),
                        ),
                        IconButton(
                          tooltip: 'Next month',
                          onPressed: D.sameDay(_month, D.startOfMonth(DateTime.now())) ? null : () => setState(() => _month = D.addMonths(_month, 1)),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                    Text('Tap a day to fix a missed check-in', style: context.text.bodySmall),
                    const SizedBox(height: Gap.sm),
                    _MonthGrid(month: _month, h: h, color: c),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({required this.month, required this.h, required this.color});
  final DateTime month;
  final HabitStats h;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = D.startOfMonth(month);
    final offset = first.weekday - 1;
    final days = D.daysInMonth(month.year, month.month);
    final today = D.today();
    return Column(
      children: [
        Row(
          children: [
            for (var k = 1; k <= 7; k++)
              Expanded(
                child: Center(
                  child: Text(D.weekdayLetter(k), style: context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant)),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var k = 0; k < offset; k++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              Builder(
                builder: (context) {
                  final day = DateTime(month.year, month.month, d);
                  final done = h.doneOn(day);
                  final future = day.isAfter(today);
                  final sched = h.habit.scheduledOn(day);
                  return Padding(
                    padding: const EdgeInsets.all(3),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      onTap: future ? null : () => toggleHabit(context, ref, h, day: day),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: done ? color : (sched && !future ? context.colors.surfaceContainerHigh : Colors.transparent),
                          borderRadius: BorderRadius.circular(Radii.sm),
                          border: D.sameDay(day, today) ? Border.all(color: color, width: 2) : null,
                        ),
                        child: Text(
                          '$d',
                          style: context.text.labelMedium!.copyWith(
                            color: done ? Colors.white : (future ? context.colors.onSurfaceVariant.withValues(alpha: 0.5) : null),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
