import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../data/models/knowledge.dart';
import '../../state/providers.dart';
import '../../state/timers.dart';
import 'study_providers.dart';

/// Study stopwatch & Pomodoro. Runs from absolute timestamps so it keeps
/// correct time across navigation, backgrounding and restarts.
class StudyTimerScreen extends ConsumerStatefulWidget {
  const StudyTimerScreen({super.key, this.subjectId, this.topicId});
  final int? subjectId;
  final int? topicId;
  @override
  ConsumerState<StudyTimerScreen> createState() => _StudyTimerScreenState();
}

class _StudyTimerScreenState extends ConsumerState<StudyTimerScreen> {
  StudyMode _mode = StudyMode.pomodoro;
  late int? _subjectId = widget.subjectId;
  late int? _topicId = widget.topicId;
  (int, int) _preset = (25, 5);

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    if (!((s.pomodoroWork == 25 && s.pomodoroBreak == 5) || (s.pomodoroWork == 50 && s.pomodoroBreak == 10))) {
      _preset = (s.pomodoroWork, s.pomodoroBreak);
    }
  }

  Future<void> _custom() async {
    var work = _preset.$1;
    var rest = _preset.$2;
    final ok = await showAppSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Custom timer', style: ctx.text.titleLarge),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    Expanded(child: Text('Focus (min)', style: ctx.text.bodyLarge)),
                    NumberStepper(value: work, min: 5, max: 180, step: 5, onChanged: (v) => set(() => work = v)),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    Expanded(child: Text('Break (min)', style: ctx.text.bodyLarge)),
                    NumberStepper(value: rest, min: 1, max: 60, onChanged: (v) => set(() => rest = v)),
                  ],
                ),
                const SizedBox(height: Gap.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use this timer')),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (ok == true) {
      setState(() => _preset = (work, rest));
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(pomodoroWork: work, pomodoroBreak: rest));
    }
  }

  Future<void> _start(List<Subject> subjects, List<Topic> topics) async {
    final subj = subjects.where((s) => s.id == _subjectId).firstOrNull;
    final topic = topics.where((t) => t.id == _topicId).firstOrNull;
    final ctrl = ref.read(studyTimerProvider.notifier);
    if (_mode == StudyMode.stopwatch) {
      ctrl.startStopwatch(subjectId: subj?.id, subjectName: subj?.name ?? 'General', topicId: topic?.id, topicName: topic?.name);
    } else {
      ctrl.startPomodoro(
        subjectId: subj?.id,
        subjectName: subj?.name ?? 'General',
        topicId: topic?.id,
        topicName: topic?.name,
        focusMin: _preset.$1,
        breakMin: _preset.$2,
      );
    }
  }

  Future<void> _stop() async {
    final saved = await ref.read(studyTimerProvider.notifier).stop();
    if (!mounted) return;
    showSnack(context, saved > 0 ? 'Saved ${D.duration(Duration(seconds: saved))} of study' : 'Sessions under 1 minute are not saved');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(studyTimerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Study timer')),
      body: t.active ? _running(t) : _setup(),
    );
  }

  Widget _setup() {
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final topics = _subjectId == null ? const <Topic>[] : (ref.watch(topicsProvider(_subjectId!)).value ?? const <Topic>[]);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      children: [
        SegmentedButton<StudyMode>(
          segments: const [
            ButtonSegment(value: StudyMode.pomodoro, label: Text('Pomodoro'), icon: Icon(Icons.av_timer_rounded)),
            ButtonSegment(value: StudyMode.stopwatch, label: Text('Stopwatch'), icon: Icon(Icons.timer_outlined)),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        if (_mode == StudyMode.pomodoro) ...[
          const FieldLabel('Timer'),
          Wrap(
            spacing: Gap.sm,
            children: [
              for (final p in const [(25, 5), (50, 10)])
                ChoiceChip(label: Text('${p.$1}/${p.$2}'), selected: _preset == p, onSelected: (_) => setState(() => _preset = p)),
              ChoiceChip(
                label: Text(_preset == (25, 5) || _preset == (50, 10) ? 'Custom' : 'Custom ${_preset.$1}/${_preset.$2}'),
                selected: !(_preset == (25, 5) || _preset == (50, 10)),
                onSelected: (_) => _custom(),
              ),
            ],
          ),
        ],
        const FieldLabel('Subject'),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            ChoiceChip(
              label: const Text('General'),
              selected: _subjectId == null,
              onSelected: (_) => setState(() {
                _subjectId = null;
                _topicId = null;
              }),
            ),
            for (final s in subjects)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: s.colorValue, radius: 5),
                label: Text(s.name),
                selected: _subjectId == s.id,
                onSelected: (_) => setState(() {
                  _subjectId = s.id;
                  _topicId = null;
                }),
              ),
          ],
        ),
        if (topics.isNotEmpty) ...[
          const FieldLabel('Topic (optional)'),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final tp in topics.where((t) => !t.done || t.id == _topicId))
                ChoiceChip(label: Text(tp.name), selected: _topicId == tp.id, onSelected: (_) => setState(() => _topicId = _topicId == tp.id ? null : tp.id)),
            ],
          ),
        ],
        const SizedBox(height: Gap.xxl),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: AppModule.study.color),
          onPressed: () => _start(subjects, topics),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_mode == StudyMode.pomodoro ? 'Start ${_preset.$1}-minute focus' : 'Start stopwatch'),
        ),
      ],
    );
  }

  Widget _running(StudyTimerState t) {
    ref.watch(clockProvider);
    final ctrl = ref.read(studyTimerProvider.notifier);
    final c = AppModule.study.color;
    final isPomo = t.mode == StudyMode.pomodoro;
    final rest = isPomo && t.phase == PomoPhase.rest;
    final color = rest ? Palette.success : c;
    final shown = isPomo ? Duration(seconds: t.phaseRemaining()) : Duration(seconds: t.elapsed());
    final progress = isPomo ? 1 - t.phaseRemaining() / t.phaseLength() : (t.elapsed() % 3600) / 3600;
    final waiting = isPomo && t.paused && t.phase == PomoPhase.focus && t.phasePausedLeft == t.focusMin * 60 && t.cycles > 0;
    return ListView(
      padding: const EdgeInsets.all(Gap.page),
      children: [
        Text(t.subjectName.isEmpty ? 'General' : t.subjectName, textAlign: TextAlign.center, style: context.text.titleLarge),
        if (t.topicName != null) Text(t.topicName!, textAlign: TextAlign.center, style: context.text.bodyMedium),
        const SizedBox(height: Gap.xxl),
        Center(
          child: ProgressRing(
            value: progress,
            size: 250,
            stroke: 12,
            color: color,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isPomo ? (rest ? 'BREAK' : 'FOCUS') : 'ELAPSED', style: context.text.labelLarge!.copyWith(color: color, letterSpacing: 2)),
                Text(D.clock(shown), style: context.text.displaySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                if (isPomo) Text('${t.cycles} ${t.cycles == 1 ? 'pomodoro' : 'pomodoros'} done', style: context.text.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.xxl),
        if (waiting)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Text('Break finished — ready for the next focus block?', textAlign: TextAlign.center, style: context.text.bodyMedium),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(iconSize: 28, tooltip: 'Stop and save', onPressed: _stop, icon: const Icon(Icons.stop_rounded)),
            const SizedBox(width: Gap.xl),
            SizedBox(
              width: 80,
              height: 80,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: color),
                iconSize: 40,
                tooltip: t.paused ? 'Resume' : 'Pause',
                onPressed: t.paused ? ctrl.resume : ctrl.pause,
                icon: Icon(t.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              ),
            ),
            const SizedBox(width: Gap.xl),
            if (isPomo)
              IconButton.filledTonal(
                iconSize: 28,
                tooltip: rest ? 'Skip break' : 'Finish focus early',
                onPressed: ctrl.skipPhase,
                icon: const Icon(Icons.skip_next_rounded),
              )
            else
              const SizedBox(width: 52),
          ],
        ),
        const SizedBox(height: Gap.xxl),
        AppCard(
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: context.colors.onSurfaceVariant),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  isPomo
                      ? 'Each completed focus block is saved automatically. You will be notified when a phase ends, even if you leave the app.'
                      : 'The stopwatch keeps running while you use other screens. Stop it to save the session.',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
