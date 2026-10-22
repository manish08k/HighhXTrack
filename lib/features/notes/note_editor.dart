import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/states.dart';
import '../../data/models/knowledge.dart';
import '../../data/repositories/note_repo.dart';
import '../../state/providers.dart';
import 'formatted_text.dart';
import 'note_providers.dart';

/// Distraction-free note editor with autosave.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.id, this.folderId});
  final int? id;
  final int? folderId;
  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  late final NoteRepo _repo;
  int? _id;
  Note? _note;
  bool _loading = true;
  bool _notFound = false;
  bool _preview = false;
  bool _dirty = false;
  Timer? _autosave;

  List<ChecklistItem> _checklist = [];
  int? _folderId;
  List<String> _tags = [];
  bool _pinned = false;
  bool _archived = false;
  DateTime _created = DateTime.now();

  @override
  void initState() {
    super.initState();
    _repo = ref.read(noteRepoProvider);
    _folderId = widget.folderId;
    _id = widget.id;
    _load();
  }

  Future<void> _load() async {
    if (_id != null) {
      final n = await _repo.get(_id!);
      if (!mounted) return;
      if (n == null) {
        setState(() {
          _notFound = true;
          _loading = false;
        });
        return;
      }
      _note = n;
      _title.text = n.title;
      _body.text = n.body;
      _checklist = n.checklist;
      _folderId = n.folderId;
      _tags = [...n.tags];
      _pinned = n.pinned;
      _archived = n.archived;
      _created = n.createdAt;
      _preview = n.body.isNotEmpty;
    }
    _title.addListener(_changed);
    _body.addListener(_changed);
    setState(() => _loading = false);
  }

  void _changed() {
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 800), _save);
  }

  Note _build() => Note(
    id: _id,
    title: _title.text.trim(),
    body: _body.text,
    checklist: _checklist.where((c) => c.text.trim().isNotEmpty).toList(),
    folderId: _folderId,
    tags: _tags,
    pinned: _pinned,
    archived: _archived,
    createdAt: _created,
    updatedAt: DateTime.now(),
  );

  /// Saves are chained so a new note can't be inserted twice.
  Future<void> _chain = Future.value();

  Future<void> _save() {
    _autosave?.cancel();
    return _chain = _chain.then((_) => _doSave());
  }

  Future<void> _doSave() async {
    if (!_dirty) return;
    final n = _build();
    if (_id == null && n.isEmpty) return;
    _dirty = false;
    try {
      final id = await _repo.save(n);
      _id ??= id;
    } catch (e) {
      _dirty = true;
      if (mounted) showSnack(context, 'Could not save the note');
    }
  }

  @override
  void dispose() {
    // Final save; repo is captured so this works after unmount.
    if (_dirty) _save();
    _autosave?.cancel();
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _wrap(String left, [String? right]) {
    right ??= left;
    final sel = _body.selection;
    final text = _body.text;
    if (!sel.isValid) {
      _body.text = '$text$left$right';
      _body.selection = TextSelection.collapsed(offset: _body.text.length - right.length);
    } else {
      final inner = sel.textInside(text);
      _body.value = TextEditingValue(
        text: sel.textBefore(text) + left + inner + right + sel.textAfter(text),
        selection: inner.isEmpty
            ? TextSelection.collapsed(offset: sel.start + left.length)
            : TextSelection(baseOffset: sel.start + left.length, extentOffset: sel.start + left.length + inner.length),
      );
    }
    _bodyFocus.requestFocus();
  }

  void _linePrefix(String prefix) {
    final sel = _body.selection;
    final text = _body.text;
    final pos = sel.isValid ? sel.start : text.length;
    final lineStart = text.lastIndexOf('\n', pos - 1 < 0 ? 0 : pos - 1) + 1;
    final adjusted = pos == 0 ? 0 : lineStart;
    _body.value = TextEditingValue(
      text: text.substring(0, adjusted) + prefix + text.substring(adjusted),
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
    _bodyFocus.requestFocus();
  }

  void _toggleFlag({bool? pinned, bool? archived}) {
    setState(() {
      if (pinned != null) _pinned = pinned;
      if (archived != null) _archived = archived;
    });
    _dirty = true;
    _save();
  }

  Future<void> _editTags() async {
    final v = await promptText(context, title: 'Tags', initial: _tags.join(', '), hint: 'Comma separated, e.g. work, ideas');
    if (v == null && _tags.isEmpty) return;
    setState(() => _tags = (v ?? '').split(',').map((t) => t.trim().replaceAll('#', '')).where((t) => t.isNotEmpty).toSet().toList());
    _dirty = true;
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off_rounded, title: 'Note not found'),
      );
    }
    final folders = ref.watch(noteFoldersProvider).value ?? const <NoteFolder>[];
    final folderName = folders.where((f) => f.id == _folderId).map((f) => f.name).firstOrNull;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: _preview ? 'Edit' : 'Preview',
              icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _preview = !_preview),
            ),
            IconButton(
              tooltip: _pinned ? 'Unpin' : 'Pin',
              icon: Icon(_pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: _pinned ? AppModule.notes.color : null),
              onPressed: () => _toggleFlag(pinned: !_pinned),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'checklist':
                    setState(() => _checklist = [..._checklist, ChecklistItem('')]);
                  case 'tags':
                    await _editTags();
                  case 'folder':
                    final id = await showModalBottomSheet<int>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(leading: const Icon(Icons.folder_off_outlined), title: const Text('No folder'), onTap: () => Navigator.pop(ctx, -1)),
                            for (final f in folders)
                              ListTile(
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(f.name),
                                selected: f.id == _folderId,
                                onTap: () => Navigator.pop(ctx, f.id),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (id != null) {
                      setState(() => _folderId = id == -1 ? null : id);
                      _dirty = true;
                      await _save();
                    }
                  case 'archive':
                    _toggleFlag(archived: !_archived);
                    if (context.mounted) Navigator.pop(context);
                  case 'delete':
                    if (_id == null) {
                      _dirty = false;
                      if (context.mounted) Navigator.pop(context);
                      return;
                    }
                    if (!await confirmDialog(context, title: 'Delete note?')) return;
                    if (!context.mounted) return;
                    final m = ScaffoldMessenger.of(context);
                    _dirty = false;
                    _autosave?.cancel();
                    final row = await _repo.delete(_id!);
                    if (row != null) undoOn(m, 'Note deleted', () => _repo.restore(row));
                    if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'checklist', child: Text('Add checklist item')),
                const PopupMenuItem(value: 'tags', child: Text('Edit tags')),
                const PopupMenuItem(value: 'folder', child: Text('Move to folder')),
                PopupMenuItem(value: 'archive', child: Text(_archived ? 'Unarchive' : 'Archive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
        bottomNavigationBar: _preview
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: context.colors.outlineVariant)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        IconButton(tooltip: 'Bold', icon: const Icon(Icons.format_bold_rounded), onPressed: () => _wrap('**')),
                        IconButton(tooltip: 'Italic', icon: const Icon(Icons.format_italic_rounded), onPressed: () => _wrap('*')),
                        IconButton(tooltip: 'Strikethrough', icon: const Icon(Icons.format_strikethrough_rounded), onPressed: () => _wrap('~~')),
                        IconButton(tooltip: 'Heading', icon: const Icon(Icons.title_rounded), onPressed: () => _linePrefix('# ')),
                        IconButton(tooltip: 'Bullet list', icon: const Icon(Icons.format_list_bulleted_rounded), onPressed: () => _linePrefix('- ')),
                        IconButton(tooltip: 'Numbered list', icon: const Icon(Icons.format_list_numbered_rounded), onPressed: () => _linePrefix('1. ')),
                        IconButton(tooltip: 'Quote', icon: const Icon(Icons.format_quote_rounded), onPressed: () => _linePrefix('> ')),
                        IconButton(
                          tooltip: 'Checklist item',
                          icon: const Icon(Icons.check_box_outlined),
                          onPressed: () => setState(() => _checklist = [..._checklist, ChecklistItem('')]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxxl),
          children: [
            TextField(
              controller: _title,
              style: context.text.headlineSmall,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Title',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Text(
              [if (_note != null) 'Edited ${D.relativeDateTime(_note!.updatedAt)}' else 'New note', ?folderName, ..._tags.map((t) => '#$t')].join(' · '),
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Gap.md),
            if (_preview)
              GestureDetector(
                onTap: () => setState(() => _preview = false),
                child: _body.text.trim().isEmpty
                    ? Text('Tap to write…', style: context.text.bodyLarge!.copyWith(color: context.colors.onSurfaceVariant))
                    : FormattedText(_body.text),
              )
            else
              TextField(
                controller: _body,
                focusNode: _bodyFocus,
                autofocus: widget.id == null,
                maxLines: null,
                minLines: 8,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: context.text.bodyLarge!.copyWith(height: 1.45),
                decoration: const InputDecoration(
                  hintText: 'Start writing…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (_checklist.isNotEmpty) ...[
              const SizedBox(height: Gap.md),
              for (var k = 0; k < _checklist.length; k++)
                _ChecklistRow(
                  key: ObjectKey(_checklist[k]),
                  item: _checklist[k],
                  autofocus: _checklist[k].text.isEmpty && k == _checklist.length - 1,
                  onChanged: () {
                    setState(() {});
                    _changed();
                  },
                  onRemove: () {
                    setState(() => _checklist = [..._checklist]..removeAt(k));
                    _changed();
                  },
                  onSubmit: () => setState(() => _checklist = [..._checklist..insert(k + 1, ChecklistItem(''))]),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _checklist = [..._checklist, ChecklistItem('')]),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatefulWidget {
  const _ChecklistRow({super.key, required this.item, required this.onChanged, required this.onRemove, required this.onSubmit, this.autofocus = false});
  final ChecklistItem item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onSubmit;
  final bool autofocus;
  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late final _c = TextEditingController(text: widget.item.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.item.done;
    return Row(
      children: [
        Checkbox(
          value: done,
          onChanged: (v) {
            widget.item.done = v ?? false;
            widget.onChanged();
          },
        ),
        Expanded(
          child: TextField(
            controller: _c,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.next,
            style: context.text.bodyLarge!.copyWith(decoration: done ? TextDecoration.lineThrough : null, color: done ? context.colors.onSurfaceVariant : null),
            decoration: const InputDecoration(
              hintText: 'List item',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
            ),
            onChanged: (v) {
              widget.item.text = v;
              widget.onChanged();
            },
            onSubmitted: (_) => widget.onSubmit(),
          ),
        ),
        IconButton(tooltip: 'Remove item', icon: const Icon(Icons.close_rounded, size: 18), onPressed: widget.onRemove),
      ],
    );
  }
}
