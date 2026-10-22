import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/icon_set.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/recurrence.dart';

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, String confirm = 'Delete', bool destructive = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Palette.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction, Duration duration = const Duration(seconds: 4)}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m != null) snackOn(m, message, actionLabel: actionLabel, onAction: onAction, duration: duration);
}

/// Shows a snackbar on a messenger captured before an async gap, so it
/// still works after the calling widget (e.g. a dismissed row) is gone.
void snackOn(ScaffoldMessengerState m, String message, {String? actionLabel, VoidCallback? onAction, Duration duration = const Duration(seconds: 4)}) {
  if (!m.mounted) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        persist: false,
        action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}

void showUndo(BuildContext context, String message, VoidCallback onUndo) =>
    showSnack(context, message, actionLabel: 'Undo', onAction: onUndo, duration: const Duration(seconds: 5));

void undoOn(ScaffoldMessengerState m, String message, VoidCallback onUndo) =>
    snackOn(m, message, actionLabel: 'Undo', onAction: onUndo, duration: const Duration(seconds: 5));

/// Runs [action] and shows a friendly snackbar if it throws.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action, {String? error}) async {
  final m = ScaffoldMessenger.maybeOf(context);
  try {
    return await action();
  } catch (e, st) {
    debugPrint('guard: $e\n$st');
    if (m != null) snackOn(m, error ?? 'Something went wrong. Please try again.');
    return null;
  }
}

Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollable,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

/// Single text input dialog.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirm = 'Save',
  TextInputType? keyboard,
}) async {
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => _PromptDialog(title: title, initial: initial, hint: hint, confirm: confirm, keyboard: keyboard),
  );
  return (r == null || r.isEmpty) ? null : r;
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.initial, required this.hint, required this.confirm, this.keyboard});
  final String title;
  final String initial;
  final String hint;
  final String confirm;
  final TextInputType? keyboard;
  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: widget.keyboard,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text.trim()), child: Text(widget.confirm)),
      ],
    );
  }
}

Future<DateTime?> pickDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) {
  final init = initial ?? DateTime.now();
  final f = first ?? DateTime(2000);
  final l = last ?? DateTime(2100);
  return showDatePicker(context: context, initialDate: init.isBefore(f) ? f : (init.isAfter(l) ? l : init), firstDate: f, lastDate: l);
}

Future<TimeOfDay?> pickTime(BuildContext context, {TimeOfDay? initial}) => showTimePicker(context: context, initialTime: initial ?? TimeOfDay.now());

/// Picker sheet for a [Recurrence], including custom intervals/weekdays.
Future<Recurrence?> pickRecurrence(BuildContext context, Recurrence current, {DateTime? anchor}) {
  return showAppSheet<Recurrence>(
    context,
    builder: (ctx) => _RecurrenceSheet(current: current, anchor: anchor ?? DateTime.now()),
  );
}

class _RecurrenceSheet extends StatefulWidget {
  const _RecurrenceSheet({required this.current, required this.anchor});
  final Recurrence current;
  final DateTime anchor;
  @override
  State<_RecurrenceSheet> createState() => _RecurrenceSheetState();
}

class _RecurrenceSheetState extends State<_RecurrenceSheet> {
  late bool custom = widget.current.isCustom;
  late RepeatFreq freq = widget.current.repeats ? widget.current.freq : RepeatFreq.weekly;
  late int interval = widget.current.interval;
  late Set<int> days = widget.current.weekdays.isEmpty ? {widget.anchor.weekday} : {...widget.current.weekdays};

  @override
  Widget build(BuildContext context) {
    final presets = <(String, Recurrence)>[
      ('Does not repeat', Recurrence.none),
      ('Daily', Recurrence.daily),
      ('Every weekday', const Recurrence(RepeatFreq.weekly, weekdays: {1, 2, 3, 4, 5})),
      ('Weekly on ${D.weekdayName(widget.anchor.weekday)}', Recurrence(RepeatFreq.weekly, weekdays: {widget.anchor.weekday})),
      ('Monthly on day ${widget.anchor.day}', Recurrence.monthly),
      ('Yearly', Recurrence.yearly),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gap.sm, bottom: Gap.sm),
            child: Text('Repeat', style: context.text.titleLarge),
          ),
          for (final (label, r) in presets)
            ListTile(
              title: Text(label),
              shape: const RoundedRectangleBorder(borderRadius: Radii.field),
              trailing: !custom && widget.current == r ? Icon(Icons.check_rounded, color: context.colors.primary) : null,
              onTap: () => Navigator.pop(context, r),
            ),
          ListTile(
            title: const Text('Custom'),
            shape: const RoundedRectangleBorder(borderRadius: Radii.field),
            trailing: Icon(custom ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            onTap: () => setState(() => custom = !custom),
          ),
          AnimatedSize(
            duration: Durations2.normal,
            curve: Curves.easeOutCubic,
            child: !custom
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Every'),
                            const SizedBox(width: Gap.sm),
                            IconButton.filledTonal(onPressed: interval > 1 ? () => setState(() => interval--) : null, icon: const Icon(Icons.remove_rounded)),
                            SizedBox(
                              width: 36,
                              child: Text('$interval', textAlign: TextAlign.center, style: context.text.titleMedium),
                            ),
                            IconButton.filledTonal(onPressed: interval < 99 ? () => setState(() => interval++) : null, icon: const Icon(Icons.add_rounded)),
                            const SizedBox(width: Gap.sm),
                            Expanded(
                              child: DropdownButtonFormField<RepeatFreq>(
                                initialValue: freq,
                                decoration: const InputDecoration(isDense: true),
                                items: [
                                  for (final f in RepeatFreq.values.skip(1))
                                    DropdownMenuItem(
                                      value: f,
                                      child: Text(switch (f) {
                                        RepeatFreq.daily => interval == 1 ? 'day' : 'days',
                                        RepeatFreq.weekly => interval == 1 ? 'week' : 'weeks',
                                        RepeatFreq.monthly => interval == 1 ? 'month' : 'months',
                                        _ => interval == 1 ? 'year' : 'years',
                                      }),
                                    ),
                                ],
                                onChanged: (f) => setState(() => freq = f ?? freq),
                              ),
                            ),
                          ],
                        ),
                        if (freq == RepeatFreq.weekly) ...[
                          const SizedBox(height: Gap.md),
                          WeekdayPicker(value: days, onChanged: (d) => setState(() => days = d.isEmpty ? days : d)),
                        ],
                        const SizedBox(height: Gap.lg),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.pop(context, Recurrence(freq, interval: interval, weekdays: freq == RepeatFreq.weekly ? days : const {})),
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Seven toggle circles, Monday first.
class WeekdayPicker extends StatelessWidget {
  const WeekdayPicker({super.key, required this.value, required this.onChanged, this.color});
  final Set<int> value;
  final ValueChanged<Set<int>> onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 1; d <= 7; d++)
          Semantics(
            button: true,
            selected: value.contains(d),
            label: D.weekdayName(d),
            child: InkResponse(
              onTap: () {
                final next = {...value};
                next.contains(d) ? next.remove(d) : next.add(d);
                onChanged(next);
              },
              radius: 24,
              child: AnimatedContainer(
                duration: Durations2.fast,
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: value.contains(d) ? c : context.colors.surfaceContainerHigh),
                child: Text(
                  D.weekdayLetter(d),
                  style: context.text.labelLarge!.copyWith(color: value.contains(d) ? Colors.white : context.colors.onSurfaceVariant),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ColorChoice extends StatelessWidget {
  const ColorChoice({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Gap.sm + 2,
      runSpacing: Gap.sm + 2,
      children: [
        for (final c in Palette.swatches)
          Semantics(
            button: true,
            selected: c.toARGB32() == value,
            label: 'Color',
            child: GestureDetector(
              onTap: () => onChanged(c.toARGB32()),
              child: AnimatedContainer(
                duration: Durations2.fast,
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.toARGB32() == value ? context.colors.onSurface : Colors.transparent, width: 2.5),
                ),
                child: c.toARGB32() == value ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
              ),
            ),
          ),
      ],
    );
  }
}

class IconChoice extends StatelessWidget {
  const IconChoice({super.key, required this.value, required this.onChanged, required this.color, this.indices});
  final int value;
  final ValueChanged<int> onChanged;
  final Color color;
  final List<int>? indices;

  @override
  Widget build(BuildContext context) {
    final list = indices ?? List.generate(kIconSet.length, (i) => i);
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        for (final i in list)
          InkWell(
            borderRadius: Radii.field,
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: Durations2.fast,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: i == value ? color.withValues(alpha: 0.18) : context.colors.surfaceContainerHigh,
                borderRadius: Radii.field,
                border: Border.all(color: i == value ? color : Colors.transparent, width: 1.5),
              ),
              child: Icon(kIconSet[i], color: i == value ? color : context.colors.onSurfaceVariant, size: 22),
            ),
          ),
      ],
    );
  }
}
