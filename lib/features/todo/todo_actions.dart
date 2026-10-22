import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogs.dart';
import '../../data/models/todo.dart';
import '../../state/providers.dart';

/// Shared todo actions with undo, used by list tiles, editor and home.
abstract final class TodoActions {
  static Future<void> toggle(BuildContext context, WidgetRef ref, Todo t) async {
    HapticFeedback.lightImpact();
    final m = ScaffoldMessenger.of(context);
    final repo = ref.read(todoRepoProvider);
    final done = !t.completed;
    final spawned = await guard(context, () => repo.setCompleted(t, done));
    if (!done) return;
    undoOn(m, t.recurrence.repeats && spawned != null ? 'Done · next one scheduled' : 'Task completed', () => repo.undoComplete(t, spawned));
  }

  static Future<void> delete(BuildContext context, WidgetRef ref, Todo t) async {
    final m = ScaffoldMessenger.of(context);
    final repo = ref.read(todoRepoProvider);
    final snap = await guard(context, () => repo.delete(t.id!));
    if (snap == null) return;
    undoOn(m, 'Task deleted', () => repo.restore(snap));
  }

  static Future<void> archive(BuildContext context, WidgetRef ref, Todo t, bool archived) async {
    final m = ScaffoldMessenger.of(context);
    final repo = ref.read(todoRepoProvider);
    await guard(context, () => repo.setArchived(t.id!, archived));
    undoOn(m, archived ? 'Task archived' : 'Task restored', () => repo.setArchived(t.id!, !archived));
  }
}
