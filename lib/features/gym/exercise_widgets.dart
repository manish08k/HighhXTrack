import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/gym.dart';
import '../../state/providers.dart';
import 'gym_providers.dart';
import 'rest_timer_bar.dart';

/// Searchable exercise picker. Returns the chosen exercise.
Future<Exercise?> pickExercise(BuildContext context, {Muscle? initialMuscle}) {
  return showAppSheet<Exercise>(context, builder: (_) => _ExercisePicker(initialMuscle: initialMuscle));
}

class _ExercisePicker extends ConsumerStatefulWidget {
  const _ExercisePicker({this.initialMuscle});
  final Muscle? initialMuscle;
  @override
  ConsumerState<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends ConsumerState<_ExercisePicker> {
  late Muscle? _muscle = widget.initialMuscle;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(exercisesProvider((_muscle, _q)));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: Row(
              children: [
                Expanded(child: Text('Add exercise', style: context.text.titleLarge)),
                TextButton.icon(
                  onPressed: () async {
                    final e = await editExercise(context, ref, muscle: _muscle);
                    if (e != null && context.mounted) Navigator.pop(context, e);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Custom'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.sm),
            child: AppTextField(hint: 'Search exercises', prefix: const Icon(Icons.search_rounded), onChanged: (v) => setState(() => _q = v)),
          ),
          ChoiceChips<Muscle?>(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            options: const [null, ...Muscle.values],
            selected: _muscle,
            label: (m) => m?.label ?? 'All',
            color: (m) => m?.color ?? context.colors.primary,
            onSelected: (m) => setState(() => _muscle = m),
          ),
          const SizedBox(height: Gap.sm),
          Expanded(
            child: AsyncBody<List<Exercise>>(
              value: list,
              builder: (items) => items.isEmpty
                  ? const EmptyState(icon: Icons.search_off_rounded, title: 'No exercises found', compact: true)
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final e = items[i];
                        return ListTile(
                          leading: Dot(e.muscle.color, size: 10),
                          title: Text(e.name),
                          subtitle: Text(e.muscle.label),
                          onTap: () => Navigator.pop(context, e),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Create or edit an exercise. Returns the saved exercise.
Future<Exercise?> editExercise(BuildContext context, WidgetRef ref, {Exercise? existing, Muscle? muscle}) {
  return showAppSheet<Exercise>(
    context,
    builder: (_) => _ExerciseSheet(existing: existing, muscle: muscle),
  );
}

class _ExerciseSheet extends ConsumerStatefulWidget {
  const _ExerciseSheet({this.existing, this.muscle});
  final Exercise? existing;
  final Muscle? muscle;
  @override
  ConsumerState<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends ConsumerState<_ExerciseSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late Muscle _muscle = widget.existing?.muscle ?? widget.muscle ?? Muscle.chest;
  late int _rest = widget.existing?.restSeconds ?? ref.read(settingsProvider).defaultRestSec;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final e = Exercise(
      id: widget.existing?.id,
      name: name,
      muscle: _muscle,
      notes: _notes.text.trim(),
      restSeconds: _rest,
      isCustom: widget.existing?.isCustom ?? true,
    );
    final id = await guard(context, () => ref.read(gymRepoProvider).saveExercise(e));
    if (id == null || !mounted) return;
    Navigator.pop(context, Exercise(id: id, name: e.name, muscle: e.muscle, notes: e.notes, restSeconds: e.restSeconds, isCustom: e.isCustom));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.existing == null ? 'New exercise' : 'Edit exercise', style: context.text.titleLarge),
          AppTextField(controller: _name, label: 'Name', autofocus: widget.existing == null, hint: 'e.g. Machine Chest Press'),
          const FieldLabel('Muscle group'),
          ChoiceChips<Muscle>(
            options: Muscle.values,
            selected: _muscle,
            wrap: true,
            label: (m) => m.label,
            color: (m) => m.color,
            onSelected: (m) => setState(() => _muscle = m),
          ),
          const FieldLabel('Default rest'),
          ChoiceChips<int>(options: kRestPresets, selected: _rest, wrap: true, label: restLabel, onSelected: (r) => setState(() => _rest = r)),
          AppTextField(controller: _notes, label: 'Notes', hint: 'Form cues, machine settings…', maxLines: 4, minLines: 2),
          const SizedBox(height: Gap.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}
