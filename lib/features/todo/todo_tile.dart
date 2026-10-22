import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/swipe.dart';
import '../../data/models/todo.dart';
import '../shell/nav.dart';
import 'todo_actions.dart';
import 'todo_editor.dart';

/// Round, priority-tinted completion checkbox.
class TodoCheck extends StatelessWidget {
  const TodoCheck({super.key, required this.done, required this.color, required this.onTap});
  final bool done;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: done,
      button: true,
      label: done ? 'Mark incomplete' : 'Mark complete',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: kTouchTarget,
          height: kTouchTarget,
          child: Center(
            child: AnimatedContainer(
              duration: Durations2.fast,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? color : Colors.transparent,
                border: Border.all(color: color, width: 2),
              ),
              child: done ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class TodoTile extends ConsumerWidget {
  const TodoTile({super.key, required this.todo, this.category, this.swipe = true});
  final Todo todo;
  final TodoCategory? category;
  final bool swipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = todo;
    final meta = <Widget>[];
    if (t.dueAt != null) {
      final overdue = t.isOverdue;
      meta.add(
        Pill(
          D.relativeDateTime(t.dueAt!, hasTime: t.hasTime),
          icon: Icons.schedule_rounded,
          color: overdue ? Palette.danger : (t.isDueToday ? context.colors.primary : null),
          dense: true,
        ),
      );
    }
    if (category != null) meta.add(Pill(category!.name, color: category!.colorValue, dense: true));
    if (t.subtasks.isNotEmpty) meta.add(Pill('${t.subtasksDone}/${t.subtasks.length}', icon: Icons.checklist_rounded, dense: true));
    if (t.recurrence.repeats) meta.add(Pill(t.recurrence.label, icon: Icons.repeat_rounded, dense: true));
    if (t.attachmentCount > 0) meta.add(Pill('${t.attachmentCount}', icon: Icons.attach_file_rounded, dense: true));

    final tile = AppCard(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.sm, Gap.md, Gap.sm),
      onTap: () => push(context, TodoEditorScreen(id: t.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TodoCheck(done: t.completed, color: t.priority.color, onTap: () => TodoActions.toggle(context, ref, t)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: Gap.md - 1, bottom: Gap.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: Durations2.fast,
                    style: context.text.bodyLarge!.copyWith(
                      fontWeight: FontWeight.w500,
                      decoration: t.completed ? TextDecoration.lineThrough : null,
                      color: t.completed ? context.colors.onSurfaceVariant : context.colors.onSurface,
                    ),
                    child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  if (t.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                  if (meta.isNotEmpty) ...[const SizedBox(height: Gap.sm), Wrap(spacing: Gap.xs + 2, runSpacing: Gap.xs, children: meta)],
                ],
              ),
            ),
          ),
          if (t.priority == Priority.high && !t.completed)
            Padding(
              padding: const EdgeInsets.only(top: Gap.md),
              child: Icon(Icons.flag_rounded, size: 18, color: Priority.high.color),
            ),
        ],
      ),
    );

    if (!swipe) return tile;
    return SwipeTile(
      key: ValueKey('todo-${t.id}-${t.completed}'),
      start: SwipeAction(
        icon: t.completed ? Icons.undo_rounded : Icons.check_rounded,
        label: t.completed ? 'Reopen' : 'Complete',
        color: Palette.success,
        onTrigger: () => TodoActions.toggle(context, ref, t),
      ),
      end: SwipeAction(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        color: Palette.danger,
        dismiss: true,
        onTrigger: () => TodoActions.delete(context, ref, t),
      ),
      child: tile,
    );
  }
}
