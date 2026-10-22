import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/inputs.dart';
import '../../data/models/planner.dart';
import '../../data/repositories/base.dart';
import '../../state/providers.dart';
import '../reminders/reminder_editor.dart';
import '../shell/nav.dart';

final linkedRemindersProvider = FutureProvider.autoDispose.family<List<Reminder>, (AppModule, int)>((ref, key) {
  ref.watchTopics([Chg.reminders]);
  return ref.read(reminderRepoProvider).forLink(key.$1.name, key.$2);
});

/// Shows reminders linked to an item and lets the user add one.
class LinkedReminders extends ConsumerWidget {
  const LinkedReminders({super.key, required this.module, required this.itemId, required this.title, this.suggestedTime});
  final AppModule module;
  final int itemId;
  final String title;
  final DateTime? suggestedTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(linkedRemindersProvider((module, itemId))).value ?? const <Reminder>[];
    final c = AppModule.reminders.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Reminders'),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Material(
              color: c.withValues(alpha: 0.1),
              borderRadius: Radii.field,
              child: ListTile(
                shape: const RoundedRectangleBorder(borderRadius: Radii.field),
                leading: Icon(Icons.notifications_active_outlined, color: c),
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text([D.relativeDateTime(r.dueAt), if (r.recurrence.repeats) r.recurrence.label].join(' · ')),
                onTap: () => push(context, ReminderEditorScreen(id: r.id)),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => push(context, ReminderEditorScreen(linkModule: module, linkId: itemId, initialTitle: title, initialDue: suggestedTime)),
          icon: Icon(Icons.add_alert_outlined, color: context.colors.primary),
          label: const Text('Add reminder'),
        ),
      ],
    );
  }
}
