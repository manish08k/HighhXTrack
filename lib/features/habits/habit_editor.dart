import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../data/models/planner.dart';
import '../../state/providers.dart';

/// Icons that suit habits (indices into kIconSet).
const kHabitIcons = [16, 18, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 15, 5, 7, 33, 34, 35, 29, 30, 6];

class HabitEditorScreen extends ConsumerStatefulWidget {
  const HabitEditorScreen({super.key, this.habit});
  final Habit? habit;
  @override
  ConsumerState<HabitEditorScreen> createState() => _HabitEditorScreenState();
}

class _HabitEditorScreenState extends ConsumerState<HabitEditorScreen> {
  late final _name = TextEditingController(text: widget.habit?.name ?? '');
  late int _icon = widget.habit?.icon ?? 16;
  late int _color = widget.habit?.color ?? Palette.swatches[8].toARGB32();
  late HabitSchedule _schedule = widget.habit?.schedule ?? HabitSchedule.daily;
  late Set<int> _days = {...?widget.habit?.weekdays};
  late int _target = widget.habit?.weeklyTarget ?? 3;
  late int? _remind = widget.habit?.remindMinutes;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Give your habit a name');
      return;
    }
    if (_schedule == HabitSchedule.weekdays && _days.isEmpty) {
      showSnack(context, 'Pick at least one day');
      return;
    }
    setState(() => _saving = true);
    final h = widget.habit;
    final habit = Habit(
      id: h?.id,
      name: _name.text.trim(),
      icon: _icon,
      color: _color,
      schedule: _schedule,
      weekdays: _schedule == HabitSchedule.weekdays ? _days : const {},
      weeklyTarget: _target,
      remindMinutes: _remind,
      archived: h?.archived ?? false,
      position: h?.position ?? 0,
      createdAt: h?.createdAt ?? DateTime.now(),
    );
    final ok = await guard(context, () => ref.read(habitRepoProvider).save(habit));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = Color(_color);
    return Scaffold(
      appBar: AppBar(title: Text(widget.habit == null ? 'New habit' : 'Edit habit')),
      bottomNavigationBar: FormActionBar(label: widget.habit == null ? 'Create habit' : 'Save changes', onPressed: _save, busy: _saving),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
        children: [
          AppTextField(controller: _name, label: 'Name', hint: 'e.g. Drink 8 glasses of water', autofocus: widget.habit == null),
          const FieldLabel('How often'),
          SegmentedButton<HabitSchedule>(
            segments: [
              for (final s in HabitSchedule.values)
                ButtonSegment(
                  value: s,
                  label: Text(s.label, style: const TextStyle(fontSize: 12.5)),
                ),
            ],
            selected: {_schedule},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _schedule = s.first),
          ),
          const SizedBox(height: Gap.md),
          if (_schedule == HabitSchedule.weekdays) WeekdayPicker(value: _days, color: c, onChanged: (d) => setState(() => _days = d)),
          if (_schedule == HabitSchedule.weekly)
            Row(
              children: [
                Expanded(child: Text('Times per week', style: context.text.bodyLarge)),
                NumberStepper(value: _target, min: 1, max: 7, onChanged: (v) => setState(() => _target = v)),
              ],
            ),
          const FieldLabel('Reminder'),
          PickerTile(
            icon: Icons.notifications_none_rounded,
            label: 'No reminder',
            value: _remind == null ? null : 'Every scheduled day at ${D.minutesOfDayLabel(_remind!)}',
            onTap: () async {
              final t = await pickTime(
                context,
                initial: _remind == null ? const TimeOfDay(hour: 8, minute: 0) : TimeOfDay(hour: _remind! ~/ 60, minute: _remind! % 60),
              );
              if (t != null) setState(() => _remind = t.hour * 60 + t.minute);
            },
            onClear: () => setState(() => _remind = null),
          ),
          const FieldLabel('Color'),
          ColorChoice(value: _color, onChanged: (v) => setState(() => _color = v)),
          const FieldLabel('Icon'),
          IconChoice(value: _icon, color: c, indices: kHabitIcons, onChanged: (v) => setState(() => _icon = v)),
        ],
      ),
    );
  }
}
