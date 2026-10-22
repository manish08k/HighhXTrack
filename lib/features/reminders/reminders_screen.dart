import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/swipe.dart';
import '../../data/models/planner.dart';
import '../../data/repositories/base.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';
import 'reminder_editor.dart';

final activeRemindersProvider = FutureProvider.autoDispose<List<Reminder>>((ref) {
  ref.watchTopics([Chg.reminders]);
  return ref.read(reminderRepoProvider).active();
});

final reminderHistoryProvider = FutureProvider.autoDispose<List<ReminderLog>>((ref) {
  ref.watchTopics([Chg.reminders]);
  return ref.read(reminderRepoProvider).history();
});

abstract final class ReminderActions {
  static Future<void> complete(BuildContext context, WidgetRef ref, Reminder r) async {
    final m = ScaffoldMessenger.of(context);
    final repo = ref.read(reminderRepoProvider);
    final undo = await guard(context, () => repo.complete(r));
    if (undo == null) return;
    undoOn(m, r.recurrence.repeats ? 'Done · next ${r.recurrence.label.toLowerCase()}' : 'Reminder completed', () => repo.undo(undo));
  }

  static Future<void> delete(BuildContext context, WidgetRef ref, Reminder r) async {
    final m = ScaffoldMessenger.of(context);
    final repo = ref.read(reminderRepoProvider);
    final undo = await guard(context, () => repo.delete(r.id!));
    if (undo == null) return;
    undoOn(m, 'Reminder deleted', () => repo.undo(undo));
  }
}

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reminders'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'History'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'rem-fab',
          tooltip: 'New reminder',
          onPressed: () => push(context, const ReminderEditorScreen()),
          child: const Icon(Icons.add_rounded),
        ),
        body: const TabBarView(children: [_Upcoming(), _History()]),
      ),
    );
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<Reminder>>(
      value: ref.watch(activeRemindersProvider),
      onRetry: () => ref.invalidate(activeRemindersProvider),
      builder: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.notifications_none_rounded,
            color: AppModule.reminders.color,
            title: 'No reminders',
            message: 'Create one-time or recurring reminders for bills, calls and more.',
            actionLabel: 'Add reminder',
            onAction: () => push(context, const ReminderEditorScreen()),
          );
        }
        final rows = <Object>[];
        String? last;
        for (final r in list) {
          final h = r.isOverdue ? 'Overdue' : D.relativeDay(r.dueAt);
          if (h != last) rows.add(last = h);
          rows.add(r);
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            if (row is String) {
              return Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : Gap.lg, bottom: Gap.sm, left: Gap.xs),
                child: Text(row, style: context.text.labelLarge!.copyWith(color: row == 'Overdue' ? Palette.danger : context.colors.onSurfaceVariant)),
              );
            }
            final r = row as Reminder;
            return Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: ReminderTile(reminder: r),
            );
          },
        );
      },
    );
  }
}

class ReminderTile extends ConsumerWidget {
  const ReminderTile({super.key, required this.reminder, this.swipe = true});
  final Reminder reminder;
  final bool swipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reminder;
    final c = AppModule.reminders.color;
    final card = AppCard(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
      onTap: () => push(context, ReminderEditorScreen(id: r.id)),
      child: Row(
        children: [
          IconBadge(r.linkModule?.icon ?? Icons.notifications_none_rounded, r.linkModule?.color ?? c),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: context.text.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Pill(D.relativeDateTime(r.dueAt), icon: Icons.schedule_rounded, color: r.isOverdue ? Palette.danger : null, dense: true),
                    if (r.recurrence.repeats) Pill(r.recurrence.label, icon: Icons.repeat_rounded, dense: true),
                    if (r.priority == Priority.high) Pill('High', icon: Icons.flag_rounded, color: Priority.high.color, dense: true),
                    if (r.linkModule != null)
                      InkWell(
                        onTap: r.linkId == null ? null : () => openItem(ref, r.linkModule!, r.linkId!),
                        child: Pill(r.linkModule!.label, icon: Icons.link_rounded, color: r.linkModule!.color, dense: true),
                      ),
                  ],
                ),
                if (r.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(r.notes, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              final repo = ref.read(reminderRepoProvider);
              switch (v) {
                case 'done':
                  await ReminderActions.complete(context, ref, r);
                case 'snooze10':
                  await repo.snooze(r, const Duration(minutes: 10));
                case 'snooze60':
                  await repo.snooze(r, const Duration(hours: 1));
                case 'tomorrow':
                  final base = r.dueAt.isAfter(DateTime.now()) ? r.dueAt : DateTime.now();
                  await repo.moveTo(r, D.addDays(base, 1));
                case 'delete':
                  if (context.mounted && await confirmDialog(context, title: 'Delete reminder?', message: r.title)) {
                    if (context.mounted) await ReminderActions.delete(context, ref, r);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'done', child: Text('Mark done')),
              PopupMenuItem(value: 'snooze10', child: Text('Snooze 10 min')),
              PopupMenuItem(value: 'snooze60', child: Text('Snooze 1 hour')),
              PopupMenuItem(value: 'tomorrow', child: Text('Move to tomorrow')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
    if (!swipe) return card;
    return SwipeTile(
      key: ValueKey('rem-${r.id}-${r.dueAt.millisecondsSinceEpoch}'),
      start: SwipeAction(
        icon: Icons.check_rounded,
        label: 'Done',
        color: Palette.success,
        dismiss: true,
        onTrigger: () => ReminderActions.complete(context, ref, r),
      ),
      end: SwipeAction(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        color: Palette.danger,
        dismiss: true,
        onTrigger: () => ReminderActions.delete(context, ref, r),
      ),
      child: card,
    );
  }
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<ReminderLog>>(
      value: ref.watch(reminderHistoryProvider),
      builder: (list) {
        if (list.isEmpty) return const EmptyState(icon: Icons.history_rounded, title: 'No history yet', message: 'Completed reminders appear here.');
        return ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 96),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  if (await confirmDialog(context, title: 'Clear history?', message: 'This removes the completion log only.', confirm: 'Clear')) {
                    await ref.read(reminderRepoProvider).clearHistory();
                  }
                },
                child: const Text('Clear history'),
              ),
            ),
            for (final l in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_rounded, color: Palette.success),
                title: Text(l.title),
                subtitle: Text('Due ${D.relativeDateTime(l.dueAt)} · done ${D.relativeDateTime(l.doneAt)}'),
              ),
          ],
        );
      },
    );
  }
}
