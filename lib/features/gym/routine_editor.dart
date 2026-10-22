import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../data/models/gym.dart';
import '../../state/providers.dart';
import 'exercise_widgets.dart';

/// Create/edit a routine (workout template), optionally scheduled weekly
/// with a reminder.
class RoutineEditorScreen extends ConsumerStatefulWidget {
  const RoutineEditorScreen({super.key, this.routine, this.fromWorkout});
  final Routine? routine;
  final Workout? fromWorkout;

  @override
  ConsumerState<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  late final _name = TextEditingController(text: widget.routine?.name ?? widget.fromWorkout?.name ?? '');
  late Set<int> _days = {...?widget.routine?.weekdays};
  late int? _remind = widget.routine?.remindMinutes;
  late List<RoutineExercise> _items =
      widget.routine?.items.toList() ??
      [
        for (final e in widget.fromWorkout?.exercises ?? const <WorkoutExercise>[])
          RoutineExercise(
            exerciseId: e.exercise.id!,
            exerciseName: e.exercise.name,
            muscle: e.exercise.muscle,
            sets: e.doneSets == 0 ? 3 : e.doneSets,
            reps: e.sets.where((s) => s.status == SetStatus.done).map((s) => s.reps).fold(0, (a, b) => b > a ? b : a).clamp(1, 100),
          ),
      ];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Give the routine a name');
      return;
    }
    setState(() => _saving = true);
    final r = Routine(
      id: widget.routine?.id,
      name: _name.text.trim(),
      weekdays: _days,
      remindMinutes: _days.isEmpty ? null : _remind,
      color: widget.routine?.color ?? 0,
    );
    final ok = await guard(context, () => ref.read(gymRepoProvider).saveRoutine(r, _items));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routine == null ? 'New routine' : 'Edit routine'),
        actions: [
          if (widget.routine != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDialog(context, title: 'Delete routine?', message: 'Past workouts are kept.')) {
                  await ref.read(gymRepoProvider).deleteRoutine(widget.routine!.id!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      bottomNavigationBar: FormActionBar(label: 'Save routine', onPressed: _save, busy: _saving),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
        children: [
          AppTextField(controller: _name, label: 'Name', hint: 'e.g. Push Day', autofocus: widget.routine == null && widget.fromWorkout == null),
          const FieldLabel('Scheduled days'),
          WeekdayPicker(value: _days, onChanged: (d) => setState(() => _days = d)),
          const SizedBox(height: Gap.sm),
          PickerTile(
            icon: Icons.notifications_none_rounded,
            label: _days.isEmpty ? 'Pick days to enable a reminder' : 'Workout reminder',
            value: _remind == null || _days.isEmpty ? null : 'Remind at ${D.minutesOfDayLabel(_remind!)}',
            onTap: () async {
              if (_days.isEmpty) return;
              final t = await pickTime(
                context,
                initial: _remind == null ? const TimeOfDay(hour: 18, minute: 0) : TimeOfDay(hour: _remind! ~/ 60, minute: _remind! % 60),
              );
              if (t != null) setState(() => _remind = t.hour * 60 + t.minute);
            },
            onClear: () => setState(() => _remind = null),
          ),
          FieldLabel('Exercises (${_items.length})'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (a, b) => setState(() {
              final l = [..._items];
              l.insert(b, l.removeAt(a));
              _items = l;
            }),
            children: [
              for (var k = 0; k < _items.length; k++)
                Padding(
                  key: ValueKey('ri-$k-${_items[k].exerciseId}'),
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: AppCard(
                    padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (_items[k].muscle != null) Dot(_items[k].muscle!.color, size: 10),
                            const SizedBox(width: Gap.sm),
                            Expanded(child: Text(_items[k].exerciseName, style: context.text.titleSmall)),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() => _items = [..._items]..removeAt(k)),
                            ),
                            ReorderableDragStartListener(
                              index: k,
                              child: const Padding(padding: EdgeInsets.all(Gap.sm), child: Icon(Icons.drag_handle_rounded)),
                            ),
                          ],
                        ),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: Gap.md,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Sets', style: context.text.bodySmall),
                                NumberStepper(
                                  value: _items[k].sets,
                                  min: 1,
                                  max: 20,
                                  onChanged: (v) => setState(() => _items = [..._items]..[k] = _items[k].copyWith(sets: v)),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Reps', style: context.text.bodySmall),
                                NumberStepper(
                                  value: _items[k].reps,
                                  min: 1,
                                  max: 100,
                                  onChanged: (v) => setState(() => _items = [..._items]..[k] = _items[k].copyWith(reps: v)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final e = await pickExercise(context);
              if (e != null) setState(() => _items = [..._items, RoutineExercise(exerciseId: e.id!, exerciseName: e.name, muscle: e.muscle)]);
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add exercise'),
          ),
        ],
      ),
    );
  }
}
