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
import '../shell/nav.dart';
import 'study_providers.dart';
import 'study_timer_screen.dart';

/// Banner for a running study timer, shown on study screens and Home.
class ActiveStudyBanner extends ConsumerWidget {
  const ActiveStudyBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(studyTimerProvider);
    if (!t.active) return const SizedBox.shrink();
    ref.watch(clockProvider);
    final pomo = t.mode == StudyMode.pomodoro;
    final c = AppModule.study.color;
    return AppCard(
      color: c.withValues(alpha: 0.12),
      borderColor: c.withValues(alpha: 0.4),
      onTap: () => push(context, const StudyTimerScreen()),
      child: Row(
        children: [
          IconBadge(pomo ? Icons.av_timer_rounded : Icons.timer_outlined, c),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.paused ? 'Paused' : (pomo ? (t.phase == PomoPhase.focus ? 'Focusing' : 'On break') : 'Studying'),
                  style: context.text.labelMedium!.copyWith(color: c),
                ),
                Text(t.subjectName.isEmpty ? 'General' : t.subjectName, style: context.text.titleSmall),
              ],
            ),
          ),
          Text(
            D.clock(Duration(seconds: pomo ? t.phaseRemaining() : t.elapsed())),
            style: context.text.titleLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// Create/edit subject sheet.
Future<int?> editSubject(BuildContext context, {Subject? existing}) => showAppSheet<int>(context, builder: (_) => _SubjectSheet(existing: existing));

class _SubjectSheet extends ConsumerStatefulWidget {
  const _SubjectSheet({this.existing});
  final Subject? existing;
  @override
  ConsumerState<_SubjectSheet> createState() => _SubjectSheetState();
}

class _SubjectSheetState extends ConsumerState<_SubjectSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _color = widget.existing?.color ?? Palette.swatches[2].toARGB32();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final e = widget.existing;
    final id = await guard(
      context,
      () => ref
          .read(studyRepoProvider)
          .saveSubject(
            Subject(
              id: e?.id,
              name: _name.text.trim(),
              color: _color,
              archived: e?.archived ?? false,
              position: e?.position ?? 0,
              createdAt: e?.createdAt ?? DateTime.now(),
            ),
          ),
    );
    if (id != null && mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.existing == null ? 'New subject' : 'Edit subject', style: context.text.titleLarge),
        AppTextField(controller: _name, label: 'Name', hint: 'e.g. DSA, Physics', autofocus: widget.existing == null, onSubmitted: (_) => _save()),
        const FieldLabel('Color'),
        ColorChoice(value: _color, onChanged: (c) => setState(() => _color = c)),
        const SizedBox(height: Gap.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _save, child: const Text('Save')),
        ),
      ],
    ),
  );
}

/// Manual session logging (for study done away from the timer).
Future<void> logSession(BuildContext context, {int? subjectId, int? topicId}) => showAppSheet<void>(
  context,
  builder: (_) => _LogSheet(subjectId: subjectId, topicId: topicId),
);

class _LogSheet extends ConsumerStatefulWidget {
  const _LogSheet({this.subjectId, this.topicId});
  final int? subjectId;
  final int? topicId;
  @override
  ConsumerState<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<_LogSheet> {
  int _minutes = 30;
  DateTime _date = D.today();
  late int? _subjectId = widget.subjectId;

  Future<void> _save() async {
    final now = DateTime.now();
    final start = D.sameDay(_date, now) ? now.subtract(Duration(minutes: _minutes)) : DateTime(_date.year, _date.month, _date.day, 18);
    await guard(
      context,
      () => ref
          .read(studyRepoProvider)
          .addSession(
            StudySession(
              subjectId: _subjectId,
              topicId: _subjectId == widget.subjectId ? widget.topicId : null,
              startedAt: start,
              durationSec: _minutes * 60,
              kind: 'manual',
            ),
          ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Log study time', style: context.text.titleLarge),
          const FieldLabel('Subject'),
          ChoiceChips<int?>(
            options: [null, ...subjects.map((s) => s.id)],
            selected: _subjectId,
            wrap: true,
            label: (id) => id == null ? 'General' : subjects.firstWhere((s) => s.id == id).name,
            onSelected: (id) => setState(() => _subjectId = id),
          ),
          const FieldLabel('Duration'),
          Row(
            children: [
              Expanded(
                child: Text(D.duration(Duration(minutes: _minutes)), style: context.text.titleMedium),
              ),
              NumberStepper(value: _minutes, min: 5, max: 600, step: 5, onChanged: (v) => setState(() => _minutes = v)),
            ],
          ),
          const FieldLabel('Date'),
          PickerTile(
            icon: Icons.event_outlined,
            label: 'Date',
            value: D.relativeDay(_date),
            onTap: () async {
              final d = await pickDate(context, initial: _date, last: DateTime.now());
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: Gap.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('Save session')),
          ),
        ],
      ),
    );
  }
}
