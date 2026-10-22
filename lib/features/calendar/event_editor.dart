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

const kEventReminderOptions = <int?>[null, 0, 5, 15, 30, 60, 1440];

String eventReminderLabel(int? m) => switch (m) {
  null => 'No reminder',
  0 => 'At start time',
  1440 => '1 day before',
  60 => '1 hour before',
  _ => '$m min before',
};

class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, this.id, this.day});
  final int? id;
  final DateTime? day;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _location = TextEditingController();
  final _form = GlobalKey<FormState>();
  CalEvent? _original;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  late DateTime _start;
  late DateTime _end;
  bool _allDay = false;
  int _color = AppModule.calendar.color.toARGB32();
  Recurrence _rec = Recurrence.none;
  int? _remind = 15;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final base = widget.day == null ? now : DateTime(widget.day!.year, widget.day!.month, widget.day!.day, now.hour, now.minute);
    _start = DateTime(base.year, base.month, base.day, base.hour + 1);
    _end = _start.add(const Duration(hours: 1));
    _load();
  }

  Future<void> _load() async {
    if (widget.id != null) {
      final e = await ref.read(eventRepoProvider).get(widget.id!);
      if (!mounted) return;
      if (e == null) {
        setState(() {
          _notFound = true;
          _loading = false;
        });
        return;
      }
      _original = e;
      _title.text = e.title;
      _notes.text = e.notes;
      _location.text = e.location;
      _start = e.start;
      _end = e.end;
      _allDay = e.allDay;
      _color = e.color;
      _rec = e.recurrence;
      _remind = e.remindBefore;
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    var start = _start;
    var end = _end;
    if (_allDay) {
      start = D.dateOnly(start);
      end = D.endOfDay(end.isBefore(start) ? start : end);
    }
    if (end.isBefore(start)) {
      showSnack(context, 'End must be after start');
      return;
    }
    setState(() => _saving = true);
    final o = _original;
    final e = CalEvent(
      id: o?.id,
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      location: _location.text.trim(),
      start: start,
      end: end,
      allDay: _allDay,
      color: _color,
      recurrence: _rec,
      remindBefore: _remind,
      createdAt: o?.createdAt ?? DateTime.now(),
    );
    final ok = await guard(context, () => ref.read(eventRepoProvider).save(e), error: 'Could not save the event.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok != null) Navigator.pop(context);
  }

  Future<void> _pickDateTime(bool isStart) async {
    final cur = isStart ? _start : _end;
    final d = await pickDate(context, initial: cur);
    if (d == null || !mounted) return;
    TimeOfDay t = TimeOfDay.fromDateTime(cur);
    if (!_allDay) {
      final picked = await pickTime(context, initial: t);
      if (picked == null) return;
      t = picked;
    }
    final v = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      if (isStart) {
        final len = _end.difference(_start);
        _start = v;
        _end = v.add(len.isNegative ? const Duration(hours: 1) : len);
      } else {
        _end = v;
      }
    });
  }

  String _fmt(DateTime d) => _allDay ? D.weekdayDayMonth(d) : '${D.weekdayDayMonth(d)}, ${D.time(d)}';

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off_rounded, title: 'Event not found'),
      );
    }
    final o = _original;
    return Scaffold(
      appBar: AppBar(
        title: Text(o == null ? 'New event' : 'Edit event'),
        actions: [
          if (o != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (!await confirmDialog(
                  context,
                  title: 'Delete event?',
                  message: o.recurrence.repeats ? 'All occurrences of this repeating event will be deleted.' : o.title,
                )) {
                  return;
                }
                if (!context.mounted) return;
                final m = ScaffoldMessenger.of(context);
                final repo = ref.read(eventRepoProvider);
                final row = await repo.delete(o.id!);
                if (row != null) undoOn(m, 'Event deleted', () => repo.restore(row));
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      bottomNavigationBar: FormActionBar(label: o == null ? 'Add event' : 'Save changes', onPressed: _save, busy: _saving),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
          children: [
            AppTextField(
              controller: _title,
              hint: 'Event title',
              autofocus: o == null,
              textStyle: context.text.titleLarge,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              title: const Text('All day'),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            PickerTile(icon: Icons.play_arrow_rounded, label: 'Starts', value: 'Starts ${_fmt(_start)}', onTap: () => _pickDateTime(true)),
            const SizedBox(height: Gap.sm),
            PickerTile(icon: Icons.stop_rounded, label: 'Ends', value: 'Ends ${_fmt(_end)}', onTap: () => _pickDateTime(false)),
            const SizedBox(height: Gap.sm),
            PickerTile(
              icon: Icons.repeat_rounded,
              label: 'Repeat',
              value: _rec.repeats ? _rec.label : null,
              onTap: () async {
                final r = await pickRecurrence(context, _rec, anchor: _start);
                if (r != null) setState(() => _rec = r);
              },
              onClear: () => setState(() => _rec = Recurrence.none),
            ),
            const FieldLabel('Reminder'),
            ChoiceChips<int?>(
              options: kEventReminderOptions,
              selected: _remind,
              wrap: true,
              label: eventReminderLabel,
              onSelected: (v) => setState(() => _remind = v),
            ),
            if (_allDay && _remind != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm, left: Gap.xs),
                child: Text('All-day reminders are relative to 9:00 AM.', style: context.text.bodySmall),
              ),
            const FieldLabel('Color'),
            ColorChoice(value: _color, onChanged: (c) => setState(() => _color = c)),
            AppTextField(controller: _location, label: 'Location', hint: 'Optional', prefix: const Icon(Icons.place_outlined)),
            AppTextField(controller: _notes, label: 'Notes', hint: 'Optional', maxLines: 5, minLines: 2),
          ],
        ),
      ),
    );
  }
}
