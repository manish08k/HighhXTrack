import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/states.dart';
import '../../state/providers.dart';
import '../../state/timers.dart';
import '../calendar/event_editor.dart';
import '../documents/document_providers.dart';
import '../gym/gym_screen.dart';
import '../gym/rest_timer_bar.dart';
import '../gym/workout_session.dart';
import '../money/budget_screen.dart';
import '../money/txn_editor.dart';
import '../notes/note_editor.dart';
import '../reminders/reminder_editor.dart';
import '../search/search_screen.dart';
import '../shell/nav.dart';
import '../study/study_timer_screen.dart';
import '../study/study_widgets.dart';
import '../todo/todo_editor.dart';
import 'home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeProvider);
    final hide = ref.watch(settingsProvider.select((s) => s.hideAmounts));
    final studyTarget = ref.watch(settingsProvider.select((s) => s.studyDailyTargetMin));
    final rest = ref.watch(restTimerProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(homeProvider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.page, Gap.lg, Gap.sm, Gap.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              D.longDate(DateTime.now()).toUpperCase(),
                              style: context.text.labelMedium!.copyWith(color: context.colors.onSurfaceVariant, letterSpacing: 1.1),
                            ),
                            const SizedBox(height: 2),
                            Text(_greeting(), style: context.text.headlineMedium),
                          ],
                        ),
                      ),
                      IconButton(tooltip: 'Search everything', onPressed: () => push(context, const SearchScreen()), icon: const Icon(Icons.search_rounded)),
                      IconButton(
                        tooltip: hide ? 'Show amounts' : 'Hide amounts',
                        onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(hideAmounts: !s.hideAmounts)),
                        icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                  child: Column(
                    children: [
                      if (rest.active) ...[
                        RestTimerBar(compact: true, onTap: () => push(context, const WorkoutSessionScreen())),
                        const SizedBox(height: Gap.sm),
                      ],
                      if (ref.watch(studyTimerProvider.select((t) => t.active))) ...[const ActiveStudyBanner(), const SizedBox(height: Gap.sm)],
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _QuickActions()),
              data.when(
                skipLoadingOnRefresh: true,
                loading: () => const SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
                error: (e, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorView(error: e, onRetry: () => ref.invalidate(homeProvider)),
                ),
                data: (d) => SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xxxl),
                  sliver: SliverList.list(
                    children: [
                      const SectionHeader('Today', padding: EdgeInsets.fromLTRB(0, Gap.md, 0, Gap.sm)),
                      LayoutBuilder(
                        builder: (context, c) {
                          final cols = c.maxWidth > 600 ? 3 : 2;
                          final w = (c.maxWidth - Gap.md * (cols - 1)) / cols;
                          final tiles = <Widget>[
                            _ModuleTile(
                              module: AppModule.todo,
                              title: 'Todo',
                              value: '${d.todoDone} / ${d.todoTotal}',
                              caption: d.todoTotal == 0 ? 'Nothing due' : 'completed',
                              progress: d.todoTotal == 0 ? null : d.todoDone / d.todoTotal,
                            ),
                            _ModuleTile(
                              module: AppModule.gym,
                              title: 'Gym',
                              value: d.activeWorkout != null ? 'In progress' : (d.todayWorkout != null ? 'Done ✓' : (d.routine?.name ?? 'Rest day')),
                              caption: d.activeWorkout != null
                                  ? d.activeWorkout!.name
                                  : (d.todayWorkout != null
                                        ? '${d.todayWorkout!.totalSets} sets · ${D.duration(d.todayWorkout!.duration)}'
                                        : (d.routine != null ? "Today's workout" : 'No routine scheduled')),
                              onTap: d.activeWorkout != null ? () => push(context, const WorkoutSessionScreen()) : null,
                            ),
                            _ModuleTile(
                              module: AppModule.habits,
                              title: 'Habits',
                              value: '${d.habitsDone} / ${d.habitsDue}',
                              caption: d.habitsDue == 0 ? 'None today' : 'completed',
                              progress: d.habitsDue == 0 ? null : d.habitsDone / d.habitsDue,
                            ),
                            _ModuleTile(
                              module: AppModule.money,
                              title: 'Money',
                              value: hide ? '•••••' : Money.format(d.money.spentToday),
                              caption: 'spent today',
                            ),
                            _ModuleTile(
                              module: AppModule.money,
                              title: 'Budget left',
                              icon: Icons.pie_chart_outline_rounded,
                              value: d.money.budget == null ? 'Set budget' : (hide ? '•••••' : Money.format(d.money.remaining!)),
                              caption: d.money.budget == null ? 'Monthly budget' : '${pct(d.money.budgetUsed.clamp(0, 9))} used this month',
                              progress: d.money.budget == null ? null : d.money.budgetUsed,
                              progressColor: d.money.budget == null ? null : budgetColor(d.money.budgetUsed),
                              onTap: () => push(context, const BudgetScreen()),
                            ),
                            _ModuleTile(
                              module: AppModule.study,
                              title: 'Study',
                              value: '${D.duration(Duration(seconds: d.studySec))} / ${D.duration(Duration(minutes: studyTarget))}',
                              caption: 'today',
                              progress: studyTarget == 0 ? null : d.studySec / (studyTarget * 60),
                            ),
                          ];
                          return Wrap(
                            spacing: Gap.md,
                            runSpacing: Gap.md,
                            children: [for (final t in tiles) SizedBox(width: w, child: t)],
                          );
                        },
                      ),
                      SectionHeader(
                        'Upcoming',
                        action: 'Calendar',
                        onAction: () => openModule(ref, AppModule.calendar),
                        padding: const EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.xs),
                      ),
                      if (d.upcoming.isEmpty && d.reminders.isEmpty)
                        AppCard(child: Text('Nothing coming up in the next 7 days.', style: context.text.bodyMedium))
                      else
                        AppCard(
                          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                          child: Column(
                            children: [
                              for (final r in d.reminders)
                                _UpcomingRow(
                                  color: r.isOverdue ? Palette.danger : AppModule.reminders.color,
                                  icon: AppModule.reminders.icon,
                                  when: r.isOverdue ? 'Overdue' : D.relativeDateTime(r.dueAt),
                                  title: r.title,
                                  onTap: () => openItem(ref, AppModule.reminders, r.id!),
                                ),
                              for (final i in d.upcoming.where((i) => i.module != AppModule.reminders))
                                _UpcomingRow(
                                  color: i.color,
                                  icon: i.module.icon,
                                  when: D.relativeDateTime(i.start, hasTime: !i.allDay),
                                  title: i.title,
                                  onTap: () => openItem(ref, i.module, i.id, kind: i.kind),
                                ),
                            ],
                          ),
                        ),
                      if (d.expiringDocs.isNotEmpty) ...[
                        SectionHeader(
                          'Documents',
                          action: 'View all',
                          onAction: () => openModule(ref, AppModule.documents),
                          padding: const EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.xs),
                        ),
                        AppCard(
                          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                          child: Column(
                            children: [
                              for (final doc in d.expiringDocs)
                                _UpcomingRow(
                                  color: doc.status.color,
                                  icon: docIcon(doc.category),
                                  when: docDaysLabel(doc),
                                  title: doc.name,
                                  onTap: () => openItem(ref, AppModule.documents, doc.id!),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SectionHeader('Modules', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
                      const ModuleGrid(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = <(IconData, String, Color, VoidCallback)>[
      (Icons.add_task_rounded, 'Task', AppModule.todo.color, () => push(context, TodoEditorScreen(initialDue: D.today()))),
      (Icons.payments_outlined, 'Expense', AppModule.money.color, () => push(context, const TxnEditorScreen())),
      (Icons.fitness_center_rounded, 'Workout', AppModule.gym.color, () => startWorkout(context, ref)),
      (Icons.add_alert_outlined, 'Reminder', AppModule.reminders.color, () => push(context, const ReminderEditorScreen())),
      (Icons.timer_outlined, 'Study', AppModule.study.color, () => push(context, const StudyTimerScreen())),
      (Icons.edit_note_rounded, 'Note', AppModule.notes.color, () => push(context, const NoteEditorScreen())),
      (Icons.event_outlined, 'Event', AppModule.calendar.color, () => push(context, const EventEditorScreen())),
    ];
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.page, vertical: Gap.sm),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
        itemBuilder: (context, i) {
          final (icon, label, color, onTap) = actions[i];
          return Semantics(
            button: true,
            label: 'Add $label',
            child: InkWell(
              borderRadius: Radii.card,
              onTap: onTap,
              child: SizedBox(
                width: 66,
                child: Column(
                  children: [
                    IconBadge(icon, color, size: 48),
                    const SizedBox(height: 6),
                    Text(label, style: context.text.labelSmall, maxLines: 1),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModuleTile extends ConsumerWidget {
  const _ModuleTile({required this.module, required this.title, required this.value, this.caption, this.progress, this.progressColor, this.onTap, this.icon});
  final AppModule module;
  final String title;
  final String value;
  final String? caption;
  final double? progress;
  final Color? progressColor;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.all(Gap.md + 2),
      onTap: onTap ?? () => openModule(ref, module),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon ?? module.icon, size: 18, color: module.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: context.text.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (caption != null) Text(caption!, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Gap.sm),
          AppProgressBar(value: progress ?? 0, color: progressColor ?? module.color, height: 5),
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.color, required this.icon, required this.when, required this.title, required this.onTap});
  final Color color;
  final IconData icon;
  final String when;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: IconBadge(icon, color, size: 36),
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(when),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}

/// Grid of all nine modules (used on Home and the More tab).
class ModuleGrid extends ConsumerWidget {
  const ModuleGrid({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 600 ? 5 : 3;
        final w = (c.maxWidth - Gap.sm * (cols - 1)) / cols;
        return Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final m in AppModule.values)
              SizedBox(
                width: w,
                child: AppCard(
                  padding: const EdgeInsets.symmetric(vertical: Gap.lg, horizontal: Gap.sm),
                  onTap: () => openModule(ref, m),
                  child: Column(
                    children: [
                      IconBadge(m.icon, m.color, size: 44),
                      const SizedBox(height: Gap.sm),
                      Text(m.label, style: context.text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
