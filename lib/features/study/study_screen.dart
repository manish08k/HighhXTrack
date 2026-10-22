import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/knowledge.dart';
import '../../state/providers.dart';
import '../../state/timers.dart';
import '../shell/nav.dart';
import 'study_providers.dart';
import 'study_timer_screen.dart';
import 'study_widgets.dart';
import 'subject_detail.dart';

class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Study'),
          actions: [
            IconButton(tooltip: 'Log time manually', icon: const Icon(Icons.edit_note_rounded), onPressed: () => logSession(context)),
            IconButton(tooltip: 'Targets', icon: const Icon(Icons.flag_outlined), onPressed: () => _targets(context, ref)),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Subjects'),
              Tab(text: 'Progress'),
              Tab(text: 'History'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'study-fab',
          backgroundColor: AppModule.study.color,
          foregroundColor: Colors.white,
          onPressed: () => push(context, const StudyTimerScreen()),
          icon: const Icon(Icons.timer_outlined),
          label: const Text('Timer'),
        ),
        body: const TabBarView(children: [_SubjectsTab(), _ProgressTab(), _HistoryTab()]),
      ),
    );
  }

  static Future<void> _targets(BuildContext context, WidgetRef ref) async {
    final s = ref.read(settingsProvider);
    final daily = await promptText(context, title: 'Daily target (minutes)', initial: '${s.studyDailyTargetMin}', keyboard: TextInputType.number);
    if (daily == null || !context.mounted) return;
    final weekly = await promptText(context, title: 'Weekly target (minutes)', initial: '${s.studyWeeklyTargetMin}', keyboard: TextInputType.number);
    final d = int.tryParse(daily);
    final w = int.tryParse(weekly ?? '');
    if (d == null || d <= 0) {
      if (context.mounted) showSnack(context, 'Enter a valid number of minutes');
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(studyDailyTargetMin: d, studyWeeklyTargetMin: (w != null && w > 0) ? w : x.studyWeeklyTargetMin));
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sum = ref.watch(studySummaryProvider).value;
    final s = ref.watch(settingsProvider);
    final c = AppModule.study.color;
    final today = sum?.todaySec ?? 0;
    final week = sum?.weekSec ?? 0;
    final dt = s.studyDailyTargetMin * 60;
    final wt = s.studyWeeklyTargetMin * 60;
    return AppCard(
      child: Row(
        children: [
          ProgressRing(
            value: dt == 0 ? 0 : today / dt,
            size: 72,
            stroke: 7,
            color: c,
            child: Text(pct((today / (dt == 0 ? 1 : dt)).clamp(0, 9)), style: context.text.labelLarge),
          ),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Today', style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant)),
                Text(
                  '${D.duration(Duration(seconds: today))} / ${D.duration(Duration(seconds: dt))}',
                  style: context.text.titleMedium,
                ),
                const SizedBox(height: Gap.sm),
                AppProgressBar(value: wt == 0 ? 0 : week / wt, color: c, height: 6),
                const SizedBox(height: 4),
                Text(
                  'Week ${D.duration(Duration(seconds: week))} / ${D.duration(Duration(seconds: wt))} · 🔥 ${sum?.streak ?? 0} day streak',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectsTab extends ConsumerWidget {
  const _SubjectsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<Subject>>(
      value: ref.watch(subjectsProvider),
      builder: (list) => ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, 96),
        children: [
          const ActiveStudyBanner(),
          if (ref.watch(studyTimerProvider.select((t) => t.active))) const SizedBox(height: Gap.md),
          const _TodayCard(),
          SectionHeader('Subjects', action: 'New', onAction: () => editSubject(context), padding: const EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.xs)),
          if (list.isEmpty)
            EmptyState(
              icon: Icons.menu_book_rounded,
              color: AppModule.study.color,
              title: 'Add your first subject',
              message: 'e.g. DSA with topics Arrays, Strings, Trees…',
              actionLabel: 'Add subject',
              onAction: () => editSubject(context),
              compact: true,
            ),
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: AppCard(
                onTap: () => push(context, SubjectDetailScreen(subjectId: s.id!)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Dot(s.colorValue, size: 12),
                        const SizedBox(width: Gap.sm),
                        Expanded(child: Text(s.name, style: context.text.titleSmall)),
                        Text(D.duration(Duration(seconds: s.totalSeconds)), style: context.text.bodySmall),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    AppProgressBar(value: s.progress, color: s.colorValue, height: 6),
                    const SizedBox(height: 4),
                    Text(s.topicCount == 0 ? 'No topics yet' : '${s.topicsDone}/${s.topicCount} topics', style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressTab extends ConsumerWidget {
  const _ProgressTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dist = ref.watch(studyDistributionProvider).value ?? const [];
    final c = AppModule.study.color;
    final dailyTarget = ref.watch(settingsProvider.select((s) => s.studyDailyTargetMin)) / 60;
    return AsyncBody<StudySummary>(
      value: ref.watch(studySummaryProvider),
      builder: (s) => ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, 96),
        children: [
          StatGrid(
            padding: EdgeInsets.zero,
            children: [
              StatTile(label: 'Total hours', value: trimNum(s.totalSec / 3600), icon: Icons.hourglass_bottom_rounded, color: c),
              StatTile(
                label: 'This week',
                value: D.duration(Duration(seconds: s.weekSec)),
                icon: Icons.date_range_rounded,
              ),
              StatTile(label: 'Study streak', value: '${s.streak} days', caption: 'Best ${s.bestStreak}', icon: Icons.local_fire_department_rounded),
              StatTile(
                label: 'Topics done',
                value: '${s.topicsDone}/${s.topicsTotal}',
                caption: s.topicsTotal == 0 ? null : pct(s.topicsDone / s.topicsTotal),
                icon: Icons.task_alt_rounded,
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          ChartCard(
            title: 'Daily study hours',
            subtitle: 'Last 14 days · dashed line is your target',
            child: SimpleBarChart(
              values: [for (final x in s.perDay) x / 3600],
              labels: [for (var k = 0; k < s.perDay.length; k++) D.weekdayLetter(D.addDays(D.today(), k - s.perDay.length + 1).weekday)],
              color: c,
              target: dailyTarget,
              highlightLast: true,
              format: (v) => '${trimNum(v)}h',
            ),
          ),
          const SizedBox(height: Gap.md),
          ChartCard(
            title: 'Subject distribution',
            subtitle: 'Last 30 days',
            child: RankedBars(items: [for (final (n, col, sec) in dist) (n, sec / 3600, Color(col), null)], format: (v) => '${trimNum(v)}h'),
          ),
          const SizedBox(height: Gap.md),
          ChartCard(
            title: 'Study calendar',
            subtitle: 'Minutes studied per day',
            child: HeatmapCalendar(
              values: s.dayTotals.map((k, v) => MapEntry(k, v / 60)),
              weeks: 26,
              color: c,
              label: (d, v) => '${D.dayMonth(d)}: ${v.round()} min',
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<StudySession>>(
      value: ref.watch(sessionsProvider(null)),
      builder: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.history_rounded,
            color: AppModule.study.color,
            title: 'No study sessions yet',
            message: 'Start the timer or log time manually.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final x = list[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Dot(x.subjectColor == null ? AppModule.study.color : Color(x.subjectColor!), size: 12),
              title: Text('${x.subjectName ?? 'General'}${x.topicName == null ? '' : ' · ${x.topicName}'}'),
              subtitle: Text('${D.relativeDateTime(x.startedAt)} · ${x.kind}'),
              trailing: Text(D.duration(x.duration), style: context.text.titleSmall),
              onTap: x.subjectId == null ? null : () => push(context, SubjectDetailScreen(subjectId: x.subjectId!)),
            );
          },
        );
      },
    );
  }
}
