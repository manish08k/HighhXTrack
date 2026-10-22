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
import '../../data/models/planner.dart';
import '../../data/repositories/base.dart';
import '../../data/repositories/study_repo.dart';
import '../../state/providers.dart';
import '../documents/document_providers.dart';
import '../shell/nav.dart';

class GlobalInsights {
  const GlobalInsights({
    required this.todoPerDay,
    required this.todoDone,
    required this.todoTotal,
    required this.workoutsPerWeek,
    required this.monthly,
    required this.habitRate,
    required this.habitTotals,
    required this.studyPerDay,
    required this.studyStreak,
    required this.expiries,
  });
  final List<int> todoPerDay;
  final int todoDone;
  final int todoTotal;
  final List<(DateTime, int, double, double)> workoutsPerWeek;
  final List<(DateTime, int, int)> monthly;
  final double habitRate;
  final Map<int, int> habitTotals;
  final List<int> studyPerDay;
  final int studyStreak;
  final List<Doc> expiries;
}

final globalInsightsProvider = FutureProvider.autoDispose<GlobalInsights>((ref) async {
  ref.watchTopics(Chg.all);
  final (done, total) = await ref.read(todoRepoProvider).overallCounts();
  final habits = await ref.read(habitRepoProvider).all();
  final study = ref.read(studyRepoProvider);
  final docs = (await ref.read(documentRepoProvider).all()).where((d) => d.expiryAt != null && (d.daysLeft ?? 0) <= 90).toList();
  return GlobalInsights(
    todoPerDay: await ref.read(todoRepoProvider).completionsPerDay(14),
    todoDone: done,
    todoTotal: total,
    workoutsPerWeek: await ref.read(gymRepoProvider).weekly(8),
    monthly: await ref.read(moneyRepoProvider).monthly(6),
    habitRate: habits.isEmpty ? 0 : habits.map((h) => h.monthRate).reduce((a, b) => a + b) / habits.length,
    habitTotals: await ref.read(habitRepoProvider).dailyTotals(D.addDays(D.today(), -7 * 18)),
    studyPerDay: await study.perDay(14),
    studyStreak: studyStreak(await study.dayTotals(from: D.addDays(D.today(), -400))),
    expiries: docs,
  );
});

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(settingsProvider.select((s) => s.hideAmounts));
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: AsyncBody<GlobalInsights>(
        value: ref.watch(globalInsightsProvider),
        onRetry: () => ref.invalidate(globalInsightsProvider),
        builder: (g) {
          final days14 = [for (var k = 13; k >= 0; k--) D.addDays(D.today(), -k)];
          final thisMonth = g.monthly.isEmpty ? null : g.monthly.last;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xxxl),
            children: [
              StatGrid(
                padding: EdgeInsets.zero,
                children: [
                  StatTile(
                    label: 'Todo completion',
                    icon: AppModule.todo.icon,
                    color: AppModule.todo.color,
                    value: g.todoTotal == 0 ? '—' : pct(g.todoDone / g.todoTotal),
                    caption: '${g.todoDone} of ${g.todoTotal} tasks',
                    onTap: () => openModule(ref, AppModule.todo),
                  ),
                  StatTile(
                    label: 'Workouts (8 wks)',
                    icon: AppModule.gym.icon,
                    color: AppModule.gym.color,
                    value: '${g.workoutsPerWeek.fold<int>(0, (a, w) => a + w.$2)}',
                    caption: 'sessions',
                    onTap: () => openModule(ref, AppModule.gym),
                  ),
                  StatTile(
                    label: 'Spent this month',
                    icon: AppModule.money.icon,
                    color: AppModule.money.color,
                    value: hide ? '•••••' : Money.format(thisMonth?.$3 ?? 0),
                    onTap: () => openModule(ref, AppModule.money),
                  ),
                  StatTile(
                    label: 'Habit consistency',
                    icon: AppModule.habits.icon,
                    color: AppModule.habits.color,
                    value: pct(g.habitRate),
                    caption: 'last 30 days',
                    onTap: () => openModule(ref, AppModule.habits),
                  ),
                  StatTile(
                    label: 'Study (14 days)',
                    icon: AppModule.study.icon,
                    color: AppModule.study.color,
                    value: D.duration(Duration(seconds: g.studyPerDay.fold(0, (a, b) => a + b))),
                    caption: '🔥 ${g.studyStreak} day streak',
                    onTap: () => openModule(ref, AppModule.study),
                  ),
                  StatTile(
                    label: 'Upcoming expiries',
                    icon: AppModule.documents.icon,
                    color: AppModule.documents.color,
                    value: '${g.expiries.length}',
                    caption: 'within 90 days',
                    onTap: () => openModule(ref, AppModule.documents),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Tasks completed',
                subtitle: 'Last 14 days',
                child: SimpleBarChart(
                  values: [for (final v in g.todoPerDay) v.toDouble()],
                  labels: [for (final d in days14) D.weekdayLetter(d.weekday)],
                  color: AppModule.todo.color,
                  highlightLast: true,
                ),
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Workout frequency',
                subtitle: 'Workouts per week',
                child: SimpleBarChart(
                  values: [for (final w in g.workoutsPerWeek) w.$2.toDouble()],
                  labels: [for (final w in g.workoutsPerWeek) D.dayMonth(w.$1)],
                  color: AppModule.gym.color,
                  highlightLast: true,
                ),
              ),
              const SizedBox(height: Gap.md),
              if (!hide)
                ChartCard(
                  title: 'Money spending',
                  subtitle: 'Expenses per month',
                  child: SimpleBarChart(
                    values: [for (final m in g.monthly) m.$3 / 100],
                    labels: [for (final m in g.monthly) D.shortMonth(m.$1)],
                    color: AppModule.money.color,
                    highlightLast: true,
                    format: (v) => v >= 1000 ? '${trimNum(v / 1000)}k' : trimNum(v, digits: 0),
                  ),
                ),
              if (!hide) const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Habit consistency',
                subtitle: 'Habits completed per day',
                child: HeatmapCalendar(values: g.habitTotals, weeks: 18, color: AppModule.habits.color),
              ),
              const SizedBox(height: Gap.md),
              ChartCard(
                title: 'Study hours',
                subtitle: 'Last 14 days',
                child: SimpleBarChart(
                  values: [for (final s in g.studyPerDay) s / 3600],
                  labels: [for (final d in days14) D.weekdayLetter(d.weekday)],
                  color: AppModule.study.color,
                  highlightLast: true,
                  format: (v) => '${trimNum(v)}h',
                ),
              ),
              const SectionHeader('Upcoming expiries', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
              if (g.expiries.isEmpty)
                AppCard(child: Text('No documents expire in the next 90 days.', style: context.text.bodyMedium))
              else
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Column(
                    children: [
                      for (final d in g.expiries)
                        ListTile(
                          leading: IconBadge(docIcon(d.category), d.status.color, size: 36),
                          title: Text(d.name),
                          subtitle: Text(docDaysLabel(d)),
                          onTap: () => openItem(ref, AppModule.documents, d.id!),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
