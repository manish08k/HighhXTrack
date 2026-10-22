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
import '../../data/models/todo.dart';
import '../../state/providers.dart';
import '../shared/attachments_section.dart';
import '../shared/linked_reminders.dart';
import 'todo_actions.dart';
import 'todo_categories.dart';
import 'todo_providers.dart';

class TodoEditorScreen extends ConsumerStatefulWidget {
  const TodoEditorScreen({super.key, this.id, this.initialDue, this.initialCategory});
  final int? id;
  final DateTime? initialDue;
  final int? initialCategory;

  @override
  ConsumerState<TodoEditorScreen> createState() => _TodoEditorScreenState();
}

class _TodoEditorScreenState extends ConsumerState<TodoEditorScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _notes = TextEditingController();
  final _newSub = TextEditingController();
  final _form = GlobalKey<FormState>();

  Todo? _original;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  Priority _priority = Priority.medium;
  int? _categoryId;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  Recurrence _recurrence = Recurrence.none;
  bool _remind = true;
  List<Subtask> _subtasks = [];
  List<StagedFile> _staged = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.id == null) {
      _dueDate = widget.initialDue;
      _categoryId = widget.initialCategory;
      setState(() => _loading = false);
      return;
    }
    final t = await ref.read(todoRepoProvider).get(widget.id!);
    if (!mounted) return;
    if (t == null) {
      setState(() {
        _loading = false;
        _notFound = true;
      });
      return;
    }
    _original = t;
    _title.text = t.title;
    _desc.text = t.description;
    _notes.text = t.notes;
    _priority = t.priority;
    _categoryId = t.categoryId;
    _dueDate = t.dueAt == null ? null : D.dateOnly(t.dueAt!);
    _dueTime = t.dueAt != null && t.hasTime ? TimeOfDay.fromDateTime(t.dueAt!) : null;
    _recurrence = t.recurrence;
    _remind = t.remind;
    _subtasks = [...t.subtasks];
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _notes.dispose();
    _newSub.dispose();
    super.dispose();
  }

  DateTime? get _dueAt {
    if (_dueDate == null) return null;
    final t = _dueTime;
    return DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day, t?.hour ?? 0, t?.minute ?? 0);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final o = _original;
    final todo = Todo(
      id: o?.id,
      title: _title.text.trim(),
      description: _desc.text.trim(),
      notes: _notes.text.trim(),
      priority: _priority,
      categoryId: _categoryId,
      dueAt: _dueAt,
      hasTime: _dueDate != null && _dueTime != null,
      recurrence: _dueDate == null ? Recurrence.none : _recurrence,
      remind: _remind,
      completed: o?.completed ?? false,
      completedAt: o?.completedAt,
      archived: o?.archived ?? false,
      createdAt: o?.createdAt ?? now,
      updatedAt: now,
    );
    final ok = await guard(context, () async {
      final id = await ref.read(todoRepoProvider).save(todo, _subtasks);
      if (_staged.isNotEmpty) await saveStaged(ref, 'todo', id, _staged);
      return true;
    }, error: 'Could not save the task.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.pop(context);
  }

  void _addSubtask() {
    final t = _newSub.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _subtasks = [..._subtasks, Subtask(title: t, position: _subtasks.length)];
      _newSub.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off_rounded, title: 'Task not found', message: 'It may have been deleted.'),
      );
    }
    final o = _original;
    final cats = ref.watch(todoCategoriesProvider).value ?? const <TodoCategory>[];
    // Keep completion state live when toggled from this screen.
    final live = o == null ? null : ref.watch(todoByIdProvider(o.id!)).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(o == null ? 'New task' : 'Edit task'),
        actions: [
          if (o != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                final current = live ?? o;
                switch (v) {
                  case 'toggle':
                    await TodoActions.toggle(context, ref, current);
                    if (context.mounted) Navigator.pop(context);
                  case 'archive':
                    await TodoActions.archive(context, ref, current, !current.archived);
                    if (context.mounted) Navigator.pop(context);
                  case 'delete':
                    if (await confirmDialog(context, title: 'Delete task?', message: current.title)) {
                      if (!context.mounted) return;
                      await TodoActions.delete(context, ref, current);
                      if (context.mounted) Navigator.pop(context);
                    }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'toggle', child: Text((live ?? o).completed ? 'Mark incomplete' : 'Mark complete')),
                PopupMenuItem(value: 'archive', child: Text((live ?? o).archived ? 'Unarchive' : 'Archive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      bottomNavigationBar: FormActionBar(label: o == null ? 'Add task' : 'Save changes', onPressed: _save, busy: _saving),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
          children: [
            AppTextField(
              controller: _title,
              hint: 'What needs to be done?',
              autofocus: o == null,
              textStyle: context.text.titleLarge,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
            ),
            const SizedBox(height: Gap.sm),
            AppTextField(controller: _desc, hint: 'Description', maxLines: 3, minLines: 1),
            const FieldLabel('Priority'),
            SegmentedButton<Priority>(
              segments: [
                for (final p in Priority.values)
                  ButtonSegment(
                    value: p,
                    label: Text(p.label),
                    icon: Icon(Icons.flag_rounded, color: p.color, size: 18),
                  ),
              ],
              selected: {_priority},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const FieldLabel('Category'),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                ChoiceChip(label: const Text('None'), selected: _categoryId == null, onSelected: (_) => setState(() => _categoryId = null)),
                for (final c in cats)
                  ChoiceChip(
                    label: Text(c.name),
                    avatar: CircleAvatar(backgroundColor: c.colorValue, radius: 5),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                  onPressed: () async {
                    final id = await editTodoCategory(context, ref);
                    if (id != null && mounted) setState(() => _categoryId = id);
                  },
                ),
              ],
            ),
            const FieldLabel('Schedule'),
            PickerTile(
              icon: Icons.event_outlined,
              label: 'Due date',
              value: _dueDate == null ? null : D.relativeDay(_dueDate!),
              onTap: () async {
                final d = await pickDate(context, initial: _dueDate);
                if (d != null) setState(() => _dueDate = d);
              },
              onClear: () => setState(() {
                _dueDate = null;
                _dueTime = null;
                _recurrence = Recurrence.none;
              }),
            ),
            const SizedBox(height: Gap.sm),
            PickerTile(
              icon: Icons.schedule_rounded,
              label: 'Due time',
              value: _dueTime?.format(context),
              onTap: () async {
                final t = await pickTime(context, initial: _dueTime);
                if (t == null) return;
                setState(() {
                  _dueTime = t;
                  _dueDate ??= D.today();
                });
              },
              onClear: () => setState(() => _dueTime = null),
            ),
            const SizedBox(height: Gap.sm),
            PickerTile(
              icon: Icons.repeat_rounded,
              label: 'Repeat',
              value: _recurrence.repeats ? _recurrence.label : null,
              onTap: () async {
                final r = await pickRecurrence(context, _recurrence, anchor: _dueDate);
                if (r != null) {
                  setState(() {
                    _recurrence = r;
                    if (r.repeats) _dueDate ??= D.today();
                  });
                }
              },
              onClear: () => setState(() => _recurrence = Recurrence.none),
            ),
            const SizedBox(height: Gap.sm),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              title: const Text('Notify me'),
              subtitle: Text(_dueTime == null ? 'At 9:00 AM on the due date' : 'At the due time'),
              value: _remind,
              onChanged: _dueDate == null ? null : (v) => setState(() => _remind = v),
            ),
            FieldLabel('Subtasks${_subtasks.isEmpty ? '' : ' · ${_subtasks.where((s) => s.done).length}/${_subtasks.length}'}'),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (a, b) => setState(() {
                final list = [..._subtasks];
                list.insert(b, list.removeAt(a));
                _subtasks = list;
              }),
              children: [
                for (var k = 0; k < _subtasks.length; k++)
                  Row(
                    key: ValueKey('sub-$k-${_subtasks[k].title}'),
                    children: [
                      Checkbox(
                        value: _subtasks[k].done,
                        onChanged: (v) => setState(() => _subtasks = [..._subtasks]..[k] = _subtasks[k].copyWith(done: v ?? false)),
                      ),
                      Expanded(
                        child: Text(
                          _subtasks[k].title,
                          style: context.text.bodyLarge!.copyWith(decoration: _subtasks[k].done ? TextDecoration.lineThrough : null),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove subtask',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _subtasks = [..._subtasks]..removeAt(k)),
                      ),
                      ReorderableDragStartListener(
                        index: k,
                        child: const Padding(padding: EdgeInsets.all(Gap.sm), child: Icon(Icons.drag_handle_rounded)),
                      ),
                    ],
                  ),
              ],
            ),
            AppTextField(
              controller: _newSub,
              hint: 'Add a subtask',
              prefix: const Icon(Icons.add_rounded),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addSubtask(),
              suffix: IconButton(tooltip: 'Add', icon: const Icon(Icons.keyboard_return_rounded), onPressed: _addSubtask),
            ),
            const FieldLabel('Notes'),
            AppTextField(controller: _notes, hint: 'Add notes', maxLines: 6, minLines: 2),
            AttachmentsSection(ownerType: 'todo', ownerId: o?.id, staged: _staged, onStagedChanged: (s) => setState(() => _staged = s)),
            if (o != null) LinkedReminders(module: AppModule.todo, itemId: o.id!, title: o.title, suggestedTime: o.dueAt),
          ],
        ),
      ),
    );
  }
}
