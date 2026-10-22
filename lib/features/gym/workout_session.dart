import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/gym.dart';
import '../../data/repositories/gym_repo.dart';
import '../../state/providers.dart';
import '../../state/timers.dart';
import '../shell/nav.dart';
import 'exercise_detail.dart';
import 'exercise_widgets.dart';
import 'gym_providers.dart';
import 'rest_timer_bar.dart';
import 'workout_detail.dart';

/// The live workout. All state is in the database (status of every set),
/// so the session survives navigation, backgrounding and restarts.
class WorkoutSessionScreen extends ConsumerWidget {
  const WorkoutSessionScreen({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref, Workout w) async {
    final pending = w.exercises.fold<int>(0, (a, e) => a + e.sets.where((s) => s.status == SetStatus.pending).length);
    if (w.totalSets == 0) {
      final discard = await confirmDialog(
        context,
        title: 'No completed sets',
        message: 'Finish anyway? An empty workout will be discarded.',
        confirm: 'Discard workout',
      );
      if (!discard) return;
      await ref.read(gymRepoProvider).deleteWorkout(w.id!);
      ref.read(restTimerProvider.notifier).stop();
      if (context.mounted) Navigator.pop(context);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Finish workout?',
      message: pending == 0 ? 'Great work! Your workout will be saved.' : '$pending uncompleted ${pending == 1 ? 'set' : 'sets'} will be removed.',
      confirm: 'Finish',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    await guard(context, () => ref.read(gymRepoProvider).finishWorkout(w.id!, notes: w.notes));
    ref.read(restTimerProvider.notifier).stop();
    HapticFeedback.heavyImpact();
    if (context.mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WorkoutDetailScreen(workoutId: w.id!, justFinished: true)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkoutProvider);
    return AsyncBody<Workout?>(
      value: active,
      loading: const Scaffold(body: LoadingView()),
      builder: (w) {
        if (w == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Workout')),
            body: EmptyState(
              icon: Icons.fitness_center_rounded,
              color: AppModule.gym.color,
              title: 'No active workout',
              message: 'Start an empty workout or pick a routine.',
              actionLabel: 'Start empty workout',
              onAction: () => ref.read(gymRepoProvider).startWorkout(name: _defaultName()),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              borderRadius: Radii.field,
              onTap: () async {
                final n = await promptText(context, title: 'Workout name', initial: w.name);
                if (n != null) await ref.read(gymRepoProvider).renameWorkout(w.id!, n);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name, overflow: TextOverflow.ellipsis),
                  _Elapsed(start: w.startedAt),
                ],
              ),
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'discard' &&
                      await confirmDialog(context, title: 'Discard workout?', message: 'All sets in this session will be deleted.', confirm: 'Discard')) {
                    await ref.read(gymRepoProvider).deleteWorkout(w.id!);
                    ref.read(restTimerProvider.notifier).stop();
                    if (context.mounted) Navigator.pop(context);
                  }
                  if (v == 'rest' && context.mounted) await showRestPicker(context, ref);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rest', child: Text('Start rest timer')),
                  PopupMenuItem(value: 'discard', child: Text('Discard workout')),
                ],
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RestTimerBar(),
                  if (ref.watch(restTimerProvider).active) const SizedBox(height: Gap.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showRestPicker(context, ref),
                          icon: const Icon(Icons.timer_outlined),
                          label: const Text('Rest'),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Palette.success, foregroundColor: Colors.white),
                          onPressed: () => _finish(context, ref, w),
                          icon: const Icon(Icons.flag_rounded),
                          label: Text('Finish · ${w.totalSets} sets'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
            children: [
              for (final we in w.exercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: _ExerciseBlock(we: we, workoutId: w.id!),
                ),
              if (w.exercises.isEmpty)
                const EmptyState(
                  icon: Icons.playlist_add_rounded,
                  title: 'Add your first exercise',
                  message: 'Pick from the library or create your own.',
                  compact: true,
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final e = await pickExercise(context);
                  if (e != null) await ref.read(gymRepoProvider).addExercise(w.id!, e.id!);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add exercise'),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _defaultName() {
  final h = DateTime.now().hour;
  final part = h < 12 ? 'Morning' : (h < 17 ? 'Afternoon' : 'Evening');
  return '$part workout';
}

class _Elapsed extends ConsumerWidget {
  const _Elapsed({required this.start});
  final DateTime start;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    return Text(
      D.clock(now.difference(start)),
      style: context.text.labelMedium!.copyWith(color: AppModule.gym.color, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class _ExerciseBlock extends ConsumerWidget {
  const _ExerciseBlock({required this.we, required this.workoutId});
  final WorkoutExercise we;
  final int workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = we.exercise;
    final stats = ref.watch(exerciseStatsProvider(e.id!)).value;
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final prev = stats?.lastSets ?? const <WorkoutSet>[];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Dot(e.muscle.color, size: 10),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: InkWell(
                  onTap: () => push(context, ExerciseDetailScreen(exerciseId: e.id!)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: context.text.titleSmall),
                        Text(
                          [
                            '${we.doneSets}/${we.sets.length} sets',
                            if (stats != null && stats.bestWeight > 0) 'PR ${fmtWeight(stats.bestWeight, unit)}',
                          ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  final repo = ref.read(gymRepoProvider);
                  switch (v) {
                    case 'notes':
                      final n = await promptText(context, title: 'Notes for ${e.name}', initial: we.notes, hint: 'e.g. seat height 4');
                      if (n != null) await repo.updateWorkoutExerciseNotes(we.id, n);
                    case 'rest':
                      if (context.mounted) await showRestPicker(context, ref, suggested: e.restSeconds, label: e.name);
                    case 'remove':
                      if (context.mounted &&
                          await confirmDialog(context, title: 'Remove ${e.name}?', message: 'Its sets in this workout will be deleted.', confirm: 'Remove')) {
                        await repo.removeWorkoutExercise(we.id);
                      }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'notes', child: Text('Notes')),
                  PopupMenuItem(value: 'rest', child: Text('Rest timer')),
                  PopupMenuItem(value: 'remove', child: Text('Remove exercise')),
                ],
              ),
            ],
          ),
          if (we.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm, right: Gap.md),
              child: Text(we.notes, style: context.text.bodySmall!.copyWith(fontStyle: FontStyle.italic)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: Gap.sm, bottom: 4),
            child: Row(
              children: [
                SizedBox(width: 36, child: Text('SET', style: _hdr(context))),
                Expanded(flex: 3, child: Text('PREVIOUS', style: _hdr(context))),
                Expanded(
                  flex: 3,
                  child: Text(unit.toUpperCase(), style: _hdr(context), textAlign: TextAlign.center),
                ),
                Expanded(
                  flex: 2,
                  child: Text('REPS', style: _hdr(context), textAlign: TextAlign.center),
                ),
                const SizedBox(width: kTouchTarget),
              ],
            ),
          ),
          for (var k = 0; k < we.sets.length; k++)
            _SetRow(
              key: ValueKey(we.sets[k].id),
              index: k,
              set: we.sets[k],
              previous: k < prev.length ? prev[k] : null,
              unit: unit,
              restSeconds: e.restSeconds,
              exerciseName: e.name,
            ),
          TextButton.icon(
            onPressed: () => ref.read(gymRepoProvider).addSet(we.id),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add set'),
          ),
        ],
      ),
    );
  }

  TextStyle _hdr(BuildContext context) => context.text.labelSmall!.copyWith(color: context.colors.onSurfaceVariant, letterSpacing: 0.8);
}

class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({super.key, required this.index, required this.set, this.previous, required this.unit, required this.restSeconds, required this.exerciseName});
  final int index;
  final WorkoutSet set;
  final WorkoutSet? previous;
  final String unit;
  final int restSeconds;
  final String exerciseName;

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late final _w = TextEditingController(text: _fmt(widget.set.weight));
  late final _r = TextEditingController(text: '${widget.set.reps}');
  final _wf = FocusNode();
  final _rf = FocusNode();
  Timer? _debounce;
  late final GymRepo _repo;

  @override
  void initState() {
    super.initState();
    // Captured so pending edits can still be flushed during dispose.
    _repo = ref.read(gymRepoProvider);
  }

  static String _fmt(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  @override
  void didUpdateWidget(_SetRow old) {
    super.didUpdateWidget(old);
    // Reflect external changes without clobbering what the user is typing.
    if (!_wf.hasFocus && double.tryParse(_w.text) != widget.set.weight && !(widget.set.weight == 0 && _w.text.isEmpty)) _w.text = _fmt(widget.set.weight);
    if (!_rf.hasFocus && int.tryParse(_r.text) != widget.set.reps) _r.text = '${widget.set.reps}';
  }

  @override
  void dispose() {
    _flush();
    _w.dispose();
    _r.dispose();
    _wf.dispose();
    _rf.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _flush);
  }

  void _flush() {
    _debounce?.cancel();
    final w = double.tryParse(_w.text.replaceAll(',', '.')) ?? 0;
    final r = int.tryParse(_r.text) ?? 0;
    if (w != widget.set.weight || r != widget.set.reps) {
      _repo.updateSet(widget.set.id!, weight: w, reps: r);
    }
  }

  Future<void> _toggleDone() async {
    _flush();
    final repo = ref.read(gymRepoProvider);
    if (widget.set.status == SetStatus.done) {
      await repo.setStatus(widget.set.id!, SetStatus.pending);
      return;
    }
    if ((int.tryParse(_r.text) ?? 0) <= 0) {
      showSnack(context, 'Enter reps before completing the set');
      return;
    }
    HapticFeedback.mediumImpact();
    await repo.setStatus(widget.set.id!, SetStatus.done);
    ref.read(restTimerProvider.notifier).start(widget.restSeconds, label: widget.exerciseName);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.set;
    final done = s.status == SetStatus.done;
    final skipped = s.status == SetStatus.skipped;
    final p = widget.previous;
    final bg = done ? Palette.success.withValues(alpha: 0.12) : Colors.transparent;
    return GestureDetector(
      onLongPress: () => _menu(context),
      child: AnimatedContainer(
        duration: Durations2.fast,
        margin: const EdgeInsets.only(right: Gap.sm, bottom: 4),
        decoration: BoxDecoration(color: bg, borderRadius: Radii.field),
        child: Opacity(
          opacity: skipped ? 0.45 : 1,
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: InkWell(
                  onTap: () => _menu(context),
                  borderRadius: Radii.field,
                  child: SizedBox(
                    height: kTouchTarget,
                    child: Center(child: Text(skipped ? '–' : '${widget.index + 1}', style: context.text.titleSmall)),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  p == null ? '—' : '${_fmt(p.weight).isEmpty ? '0' : _fmt(p.weight)}×${p.reps}',
                  style: context.text.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(flex: 3, child: _num(_w, _wf, decimal: true, enabled: !skipped)),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: _num(_r, _rf, decimal: false, enabled: !skipped)),
              SizedBox(
                width: kTouchTarget,
                child: skipped
                    ? IconButton(
                        tooltip: 'Restore set',
                        icon: const Icon(Icons.undo_rounded),
                        onPressed: () => ref.read(gymRepoProvider).setStatus(s.id!, SetStatus.pending),
                      )
                    : IconButton(
                        tooltip: done ? 'Mark not done' : 'Complete set',
                        onPressed: _toggleDone,
                        icon: AnimatedSwitcher(
                          duration: Durations2.fast,
                          child: Icon(
                            done ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                            key: ValueKey(done),
                            color: done ? Palette.success : context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _num(TextEditingController c, FocusNode f, {required bool decimal, required bool enabled}) => SizedBox(
    height: 40,
    child: TextField(
      controller: c,
      focusNode: f,
      enabled: enabled,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [decimal ? decimalFormatter : FilteringTextInputFormatter.digitsOnly],
      style: context.text.titleSmall,
      onChanged: (_) => _changed(),
      onSubmitted: (_) => _flush(),
      onTapOutside: (_) {
        if (f.hasFocus) {
          f.unfocus();
          _flush();
        }
      },
      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10), hintText: '0'),
    ),
  );

  Future<void> _menu(BuildContext context) async {
    final repo = ref.read(gymRepoProvider);
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.set.status != SetStatus.skipped)
              ListTile(leading: const Icon(Icons.skip_next_rounded), title: const Text('Skip set'), onTap: () => Navigator.pop(ctx, 'skip')),
            if (widget.set.status != SetStatus.pending)
              ListTile(leading: const Icon(Icons.restart_alt_rounded), title: const Text('Reset set'), onTap: () => Navigator.pop(ctx, 'reset')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete set'), onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    switch (v) {
      case 'skip':
        await repo.setStatus(widget.set.id!, SetStatus.skipped);
      case 'reset':
        await repo.setStatus(widget.set.id!, SetStatus.pending);
      case 'delete':
        await repo.deleteSet(widget.set.id!);
    }
  }
}
