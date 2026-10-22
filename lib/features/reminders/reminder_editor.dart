import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/recurrence.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/planner.dart';
import '../../state/providers.dart';
import '../shell/nav.dart';

/// Modules a reminder can be linked to.
const kLinkableModules = [AppModule.todo, AppModule.gym, AppModule.calendar, AppModule.documents, AppModule.study];

class ReminderEditorScreen extends ConsumerStatefulWidget {
  const ReminderEditorScreen({super.key, this.id, this.linkModule, this.linkId, this.initialTitle, this.initialDue});
  final int? id;
  final AppModule? linkModule;
  final int? linkId;
  final String? initialTitle;
  final DateTime? initialDue;

  @override
  ConsumerState<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends ConsumerState<ReminderEditorScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  Reminder? _original;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  late DateTime _date;
  late TimeOfDay _time;
  Recurrence _recurrence = Recurrence.none;
  Priority _priority = Priority.medium;
  AppModule? _linkModule;
  int? _linkId;

  @override
  void initState() {
    super.initState();
    final base = widget.initialDue != null && widget.initialDue!.isAfter(DateTime.now()) ? widget.initialDue! : DateTime.now().add(const Duration(hours: 1));
    _date = D.dateOnly(base);
    _time = TimeOfDay(hour: base.hour, minute: widget.initialDue != null ? base.minute : 0);
    _title.text = widget.initialTitle ?? '';
    _linkModule = widget.linkModule;
    _linkId = widget.linkId;
    _load();
  }

  Future<void> _load() async {
    if (widget.id == null) {
      setState(() => _loading = false);
      return;
    }
    final r = await ref.read(reminderRepoProvider).get(widget.id!);
    if (!mounted) return;
    if (r == null) {
      setState(() {
        _loading = false;
        _notFound = true;
      });
      return;
    }
    _original = r;
    _title.text = r.title;
    _notes.text = r.notes;
    _date = D.dateOnly(r.dueAt);
    _time = TimeOfDay.fromDateTime(r.dueAt);
    _recurrence = r.recurrence;
    _priority = r.priority;
    _linkModule = r.linkModule;
    _linkId = r.linkId;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _due => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_recurrence.repeats && !_due.isAfter(DateTime.now()) && _original?.dueAt != _due) {
      showSnack(context, 'Pick a time in the future');
      return;
    }
    setState(() => _saving = true);
    final o = _original;
    // Changing the schedule resets the series anchor.
    final scheduleChanged = o == null || o.dueAt != _due || o.recurrence != _recurrence;
    final r = Reminder(
      id: o?.id,
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      dueAt: _due,
      anchorAt: scheduleChanged ? _due : o.anchorAt,
      recurrence: _recurrence,
      priority: _priority,
      linkModule: _linkModule,
      linkId: _linkModule == null ? null : _linkId,
      completed: false,
      createdAt: o?.createdAt ?? DateTime.now(),
    );
    final ok = await guard(context, () => ref.read(reminderRepoProvider).save(r), error: 'Could not save the reminder.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off_rounded, title: 'Reminder not found'),
      );
    }
    final o = _original;
    return Scaffold(
      appBar: AppBar(
        title: Text(o == null ? 'New reminder' : 'Edit reminder'),
        actions: [
          if (o != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (!await confirmDialog(context, title: 'Delete reminder?', message: o.title)) return;
                if (!context.mounted) return;
                final m = ScaffoldMessenger.of(context);
                final repo = ref.read(reminderRepoProvider);
                final undo = await repo.delete(o.id!);
                if (undo != null) undoOn(m, 'Reminder deleted', () => repo.undo(undo));
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      bottomNavigationBar: FormActionBar(label: o == null ? 'Add reminder' : 'Save changes', onPressed: _save, busy: _saving),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
          children: [
            AppTextField(
              controller: _title,
              hint: 'Remind me to…',
              autofocus: o == null && widget.initialTitle == null,
              textStyle: context.text.titleLarge,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
            ),
            const FieldLabel('When'),
            Row(
              children: [
                Expanded(
                  child: PickerTile(
                    icon: Icons.event_outlined,
                    label: 'Date',
                    value: D.relativeDay(_date),
                    onTap: () async {
                      final d = await pickDate(context, initial: _date);
                      if (d != null) setState(() => _date = d);
                    },
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: PickerTile(
                    icon: Icons.schedule_rounded,
                    label: 'Time',
                    value: _time.format(context),
                    onTap: () async {
                      final t = await pickTime(context, initial: _time);
                      if (t != null) setState(() => _time = t);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            PickerTile(
              icon: Icons.repeat_rounded,
              label: 'Repeat',
              value: _recurrence.repeats ? _recurrence.label : null,
              onTap: () async {
                final r = await pickRecurrence(context, _recurrence, anchor: _date);
                if (r != null) setState(() => _recurrence = r);
              },
              onClear: () => setState(() => _recurrence = Recurrence.none),
            ),
            const FieldLabel('Priority'),
            SegmentedButton<Priority>(
              segments: [for (final p in Priority.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_priority},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const FieldLabel('Link to'),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                ChoiceChip(label: const Text('Nothing'), selected: _linkModule == null, onSelected: (_) => setState(() => _linkModule = null)),
                for (final m in kLinkableModules)
                  ChoiceChip(
                    avatar: Icon(m.icon, size: 16, color: m.color),
                    label: Text(m.label),
                    selected: _linkModule == m,
                    onSelected: (_) => setState(() {
                      if (_linkModule != m) _linkId = (m == widget.linkModule) ? widget.linkId : null;
                      _linkModule = m;
                    }),
                  ),
              ],
            ),
            if (_linkModule != null && _linkId != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: TextButton.icon(
                  onPressed: () => openItem(ref, _linkModule!, _linkId!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text('Open linked ${_linkModule!.label.toLowerCase()} item'),
                ),
              ),
            const FieldLabel('Notes'),
            AppTextField(controller: _notes, hint: 'Optional details', maxLines: 5, minLines: 2),
          ],
        ),
      ),
    );
  }
}
